# cruduserhelm

## Доступ к Grafana

Пробросить порт Grafana на локальную машину:

```bash
kubectl port-forward svc/grafana-service 3000:3000
```

Открыть в браузере: http://localhost:3000

Логин: `admin`
Пароль: `admin`