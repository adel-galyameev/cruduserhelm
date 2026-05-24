# Helm chart: crud user Service

## Описание

Данное домашнее задание демонстрирует создание минимального CRUD сервиса в Kubernetes с использованием Helm чарта.

## Архитектура

- **Application**: HTTP-сервис, отвечающий на порту 8080
- **Endpoint**: описаны в приложенной postman коллекции
- **Docker Image**: `adelgalyameev/cruduser:0.1`
- **Host**: `arch.homework`

## Структура проекта

```
.
├── cruduserchart                          # Helm chart
├── user_crud.postman_collection.json      # Postman collection
├── newman.png                             # Скрин с результатом прогона коллекции через newman
```

## Проверка работы

### Предварительные требования

- Minikube запущен
- установлен  nginx через helm (как в прошлом уроке)

### Проверка helm чарта (выполнять в корне репозитория)

```bash
helm template cruduser ./cruduserchart
```

**Ожидаемый ответ:**

вывод в консоль всех описанных манифестов

### Запуск helm чарта (выполнять в корне репозитория)

```bash
helm install cruduser ./cruduserchart
```

**Ожидаемый ответ:**

```bash
NAME: cruduser
LAST DEPLOYED: Mon May  4 12:37:17 2026
NAMESPACE: default
STATUS: deployed
REVISION: 1
```

отдельных команд на проливку миграции в ДБ не нужно выполнять, миграция реализована через Job

### Остановка helm чарта

```bash
helm uninstall cruduser
```

**Ожидаемый ответ:**

```bash
release "cruduser" uninstalled
```


### Задание со звездой ⭐ (Добавить шаблонизацию приложения в helm чартах)

Абсолютно все манифесты описаны с помощью одно helm чарта и запускаются одной командой
