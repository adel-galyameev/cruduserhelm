# AGENTS.md

## Quick start

```bash
helm template cruduser ./cruduserchart         # dry-run / lint
helm install cruduser ./cruduserchart          # deploy everything
helm test cruduser                             # basic connectivity test
helm uninstall cruduser                        # teardown
```

All commands from repo root.

## Architecture

One Helm v2 chart (`cruduserchart/`) that deploys everything in a single `helm install`:

| Resource | Key config |
|---|---|
| App Deployment | `adelgalyameev/cruduser:0.1`, port 8080, probes at `/actuator/health/{liveness,readiness}` |
| PostgreSQL StatefulSet | `postgres:13.3`, port 5432, service name: `postgresql-db-service` |
| DB migration Job | Helm hook `post-install,post-upgrade`, runs `psql` via `postgres:13.3-alpine`, waits for PG with `pg_isready` init container |
| Postgres Exporter | Deployed as a sidecar-like Deployment, connects to `postgresql-db-service`, exposes metrics on port 9187 |
| Prometheus | Enabled by default, scrapes app (`/actuator/prometheus`), nginx-ingress-controller (`/metrics`, port 10254), and kubelet cadvisor (`/metrics/cadvisor` via k8s API proxy). Uses dedicated SA `prometheus-sa` with `nodes/proxy` RBAC. |
| Grafana | Enabled by default, admin/admin, port-forward: `kubectl port-forward svc/grafana-service 3000:3000`; dashboard includes app + nginx ingress + DB metrics panels |
| Ingress | `arch.homework` → nginx, class `nginx`, references external controller named `nginx-ingress-root` |

## Important quirks

- **Prerequisites**: Minikube running, nginx ingress controller installed via Helm (deployed separately, not part of this chart).
- **Nginx ingress metrics**: Scrape target hardcoded to `nginx-ingress-nginx-controller.m.svc.cluster.local:10254` — if your controller is in a different namespace or metrics are not enabled, update `prometheus-config.yaml`.
- **Host resolution**: `arch.homework` must resolve to minikube IP (add to `/etc/hosts` after `minikube ip`).
- **Passwords**: Values like `secret.datasourcePassword` are base64-encoded strings (e.g. `dXNlclBhc3N3b3Jk`) stored in Kubernetes `stringData` — the app receives the literal base64 string, not the decoded value.
- **Two label namespaces**: `cruduserchart.labels` for app/ingress/monitoring resources, `db.labels` for PostgreSQL resources.
- **No CI, no pre-commit, no linter/formatter config** in this repo.
- **Testing**: only `helm test` (busybox wget pod) and `user_crud.postman_collection.json` (needs `{{BASE_HOST}}` variable set to `http://arch.homework`).
- **DB migration SQL** lives in `configMapMigrationDb.yaml`; the Job auto-succeeds on install/upgrade and is deleted on success.
