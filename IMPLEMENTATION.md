# Implementation Report

## Обзор

В Helm-чарт `cruduserchart/` внесены изменения по трём требованиям ТЗ:

1. **Метрики nginx-ingress-controller** — дашборд + scrape-конфиг
2. **Системные метрики подов** (CPU, Memory) — дашборд + cadvisor scrape
3. **Метрики PostgreSQL** — экспортёр + дашборд

Итоговый дашборд Grafana содержит **11 панелей** (было 3). Prometheus scraper содержит **5 таргетов** (был 1).

---

## 1. Метрики nginx-ingress-controller

### Цель

Добавить в дашборд графики Latency (p50/p95/p99/max), RPS и Error Rate (5xx) с nginx-ingress-controller.

### Что сделано

#### 1.1 Включение метрик на nginx-ingress-controller (kubectl, вне чарта)

nginx-ingress-controller развёрнут отдельно (namespace `m`). Метрики были выключены.

```bash
# Включить сбор метрик в контроллере
kubectl patch daemonset -n m nginx-ingress-nginx-controller --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--enable-metrics"}
]'

# Открыть порт 10254 в сервисе
kubectl patch svc -n m nginx-ingress-nginx-controller --type='json' -p='[
  {"op": "add", "path": "/spec/ports/-", "value": {"name": "metrics", "port": 10254, "targetPort": 10254, "protocol": "TCP"}}
]'
```

Флаг `--metrics-port` **не существует** в ingress-nginx v1.15.1 — правильный флаг: `--enable-metrics`. Метрики отдаются на `--healthz-port` (по умолчанию 10254).

#### 1.2 Prometheus scrape-конфиг (`prometheus-config.yaml`)

Добавлен job `nginx-ingress`:

```yaml
- job_name: 'nginx-ingress'
  metrics_path: '/metrics'
  static_configs:
    - targets: ['nginx-ingress-nginx-controller.m.svc.cluster.local:10254']
```

Значение `m` — namespace, в котором установлен nginx-ingress. Если установлен в другом namespace — нужно поправить.

#### 1.3 Панели дашборда (`grafana-dashboard-json.yaml`)

Три панели добавлены после application-панелей (y=24, 32, 40):

| Панель | PromQL | Легенда |
|---|---|---|
| nginx Latency | `histogram_quantile(0.50/0.95/0.99/1.0, sum(rate(nginx_ingress_controller_request_duration_seconds_bucket{ingress="nginx-ingress-root"}[1m])) by (le, host))` | p50/p95/p99/max по host |
| nginx RPS | `sum(rate(nginx_ingress_controller_requests{ingress="nginx-ingress-root"}[1m])) by (host)` | rps по host |
| nginx Error Rate | `sum(rate(nginx_ingress_controller_requests{ingress="nginx-ingress-root", status=~"5.."}[1m])) by (host)` | 5xx по host |

Фильтр `ingress="nginx-ingress-root"` соответствует имени Ingress-ресурса из `values.yaml`.

**Важно:** У метрики `nginx_ingress_controller_request_duration_seconds` нет суффикса `_max`. max считается через `histogram_quantile(1.0, ...)`.

---

## 2. Системные метрики подов (CPU, Memory)

### Цель

Добавить в дашборд графики потребления памяти и CPU подами приложения из системных метрик Kubernetes (cadvisor).

### Что сделано

#### 2.1 RBAC для Prometheus (`prometheus-rbac.yaml` — новый файл)

Prometheus нужно права `nodes/proxy` для доступа к kubelet через API-прокси Kubernetes.

Созданы:

- **ServiceAccount** `prometheus-sa` (выделенный, не default)
- **ClusterRole** `prometheus-node-reader`:
  - `nodes/proxy` — `get, create`
  - `nodes` — `get, list, watch`
- **ClusterRoleBinding** (привязывает SA к ClusterRole)

#### 2.2 Prometheus deployment (`prometheus-deployment.yaml`)

Добавлен `serviceAccountName: prometheus-sa` в spec пода.

#### 2.3 Scrape-конфиг (`prometheus-config.yaml`)

Добавлен job `kubelet-cadvisor`:

```yaml
- job_name: 'kubelet-cadvisor'
  kubernetes_sd_configs:
    - role: node
  scheme: https
  tls_config:
    insecure_skip_verify: true
  authorization:
    credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
  metrics_path: /metrics/cadvisor
  relabel_configs:
    - target_label: __address__
      replacement: kubernetes.default.svc:443
    - source_labels: [__meta_kubernetes_node_name]
      regex: (.+)
      target_label: __metrics_path__
      replacement: /api/v1/nodes/${1}/proxy/metrics/cadvisor
```

Как это работает:
1. Prometheus находит все ноды через `kubernetes_sd_configs`
2. Заменяет `__address__` на `kubernetes.default.svc:443` (Kubernetes API)
3. Формирует `__metrics_path__` как `/api/v1/nodes/<имя_ноды>/proxy/metrics/cadvisor`
4. Аутентифицируется ServiceAccount-токеном, подмонтированным в под

#### 2.4 Панели дашборда

Две панели (y=48, 56):

| Панель | PromQL | Ед. изм. |
|---|---|---|
| Pod Memory Usage | `container_memory_working_set_bytes{namespace="default", pod=~"cruduser-deployment.*"}` | bytes |
| Pod CPU Usage | `rate(container_cpu_usage_seconds_total{namespace="default", pod=~"cruduser-deployment.*"}[1m])` | cores |

Фильтр по `pod=~"cruduser-deployment.*"` — паттерн имени подов приложения.

**Примечание:** В cadvisor-метриках Minikube лейбл `container` может отсутствовать. Фильтрация идёт по `pod` + `namespace`.

---

## 3. Метрики PostgreSQL

### Цель

Инструментировать БД через postgres-exporter, добавить метрики в дашборд.

### Что сделано

#### 3.1 Postgres Exporter Deployment (`postgres-exporter-deployment.yaml` — новый файл)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
spec:
  containers:
    - name: postgres-exporter
      image: prometheuscommunity/postgres-exporter:latest
      command:
        - sh
        - -c
        - "DATA_SOURCE_NAME=postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME?sslmode=disable /bin/postgres_exporter"
      env:
        - name: DB_HOST
          value: "postgresql-db-service"
        - name: DB_USER
          valueFrom:
            configMapKeyRef: {name: "postgresql-db-config", key: POSTGRES_USER}
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef: {name: "postgresql-db-secret", key: POSTGRES_PASSWORD}
        - name: DB_NAME
          valueFrom:
            configMapKeyRef: {name: "postgresql-db-config", key: POSTGRES_db}
```

**Важный нюанс:** `DATA_SOURCE_NAME` нельзя собрать через `$(VAR)` в `env.value` — Kubernetes не раскрывает такие ссылки в env-переменных. Используется `command` с `sh -c`, где shell раскрывает `$DB_USER`, `$DB_PASSWORD` и т.д.

Пароль БД (`dXNlclBhc3N3b3Jk`) хранится как есть в `stringData` секрета — это **не base64-декодированное значение**, а именно эта строка является паролем для PostgreSQL.

#### 3.2 Postgres Exporter Service (`postgres-exporter-service.yaml` — новый файл)

ClusterIP service на порт 9187, селектор `app: postgres-exporter`.

#### 3.3 Prometheus scrape-конфиг

Добавлен job (условно, по `postgresExporter.enabled`):

```yaml
- job_name: 'postgres-exporter'
  static_configs:
    - targets: ['postgres-exporter:9187']
```

#### 3.4 Панели дашборда

Три панели (y=64, 72, 80):

| Панель | PromQL | Ед. изм. |
|---|---|---|
| DB Active Connections | `pg_stat_database_numbackends{datname="user"}` | count |
| DB Transactions | `rate(pg_stat_database_xact_commit{datname="user"}[1m])` и `rate(pg_stat_database_xact_rollback{datname="user"}[1m])` | rps |
| DB Rows Activity | `rate(pg_stat_database_tup_inserted{datname="user"}[1m])`, `...tup_updated...`, `...tup_deleted...` | rps |

Фильтр `datname="user"` — имя БД из `values.yaml` (`configDb.db: user`).

---

## Изменённые и новые файлы

### Новые файлы

| Файл | Назначение |
|---|---|
| `templates/prometheus-rbac.yaml` | ServiceAccount + ClusterRole + ClusterRoleBinding для Prometheus |
| `templates/postgres-exporter-deployment.yaml` | Deployment postgres-exporter |
| `templates/postgres-exporter-service.yaml` | Service postgres-exporter |

### Изменённые файлы

| Файл | Что изменено |
|---|---|
| `values.yaml` | Добавлена секция `postgresExporter` |
| `templates/prometheus-config.yaml` | Jobs: `nginx-ingress`, `kubelet-cadvisor`, `postgres-exporter` |
| `templates/prometheus-deployment.yaml` | `serviceAccountName: prometheus-sa` |
| `templates/grafana-dashboard-json.yaml` | +8 панелей (3 nginx, 2 pod, 3 DB) |

### Прочие изменения

| Файл | Что изменено |
|---|---|
| `AGENTS.md` | Обновлена под текущую архитектуру |

---

## Команды для воспроизведения

```bash
# 1. Развернуть/обновить чарт
helm upgrade --install cruduser ./cruduserchart

# 2. Перезапустить поды, использующие ConfigMap (не перезапускаются автоматически)
kubectl rollout restart deployment -n default prometheus-deployment grafana-deployment

# 3. Включить метрики на nginx-ingress (если ещё не включены)
kubectl patch daemonset -n m nginx-ingress-nginx-controller --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--enable-metrics"}
]'
kubectl patch svc -n m nginx-ingress-nginx-controller --type='json' -p='[
  {"op": "add", "path": "/spec/ports/-", "value": {"name": "metrics", "port": 10254, "targetPort": 10254, "protocol": "TCP"}}
]'

# 4. Прокси для доступа к Grafana
kubectl port-forward svc/grafana-service 3000:3000
# → http://localhost:3000, admin/admin
```

---

## Таргеты Prometheus (итог)

| Job | Источник | Порт |
|---|---|---|
| `cruduser` | App `/actuator/prometheus` | 8080 |
| `nginx-ingress` | nginx-ingress-controller `/metrics` | 10254 |
| `kubelet-cadvisor` | kubelet `/metrics/cadvisor` (через API proxy) | 443 |
| `postgres-exporter` | postgres-exporter `/metrics` | 9187 |

---

## Дашборд Grafana (итог)

11 панелей, y=0..88:

| y | Панель | Данные |
|---|---|---|
| 0 | Latency (p50, p95, p99, max) | App: `http_server_requests_seconds` |
| 8 | RPS by endpoint | App: `http_server_requests_seconds_count` |
| 16 | Error Rate (5xx) | App: `http_server_requests_seconds_count` |
| 24 | nginx Latency (p50, p95, p99, max) | nginx: `nginx_ingress_controller_request_duration_seconds` |
| 32 | nginx RPS | nginx: `nginx_ingress_controller_requests` |
| 40 | nginx Error Rate (5xx) | nginx: `nginx_ingress_controller_requests` |
| 48 | Pod Memory Usage | cadvisor: `container_memory_working_set_bytes` |
| 56 | Pod CPU Usage | cadvisor: `container_cpu_usage_seconds_total` |
| 64 | DB Active Connections | postgres: `pg_stat_database_numbackends` |
| 72 | DB Transactions | postgres: `pg_stat_database_xact_commit/rollback` |
| 80 | DB Rows Activity | postgres: `pg_stat_database_tup_inserted/updated/deleted` |
