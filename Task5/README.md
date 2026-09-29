# Изоляция трафика в Kubernetes

Четыре сервиса развёрнуты в одном `namespace`, у Pod метка `role`. `admin-back-end-api` - новый сервис: ему разрешена связь только с `admin-front-end` по TCP/80. Обычная пара `front-end` ↔ `back-end-api` имеет такое же двустороннее разрешение. Остальные входящие и исходящие соединения запрещены; исключение - DNS к CoreDNS для разрешения имён Service. Ответный трафик на разрешённое соединение пропускается автоматически.

Команды для отдельного профиля Minikube с CNI Calico:

```bash
minikube start -p pd-sprint5 --driver=docker --cni=calico --cpus=2 --memory=3072
kubectl --context=pd-sprint5 create namespace pd-network-demo
kubectl --context=pd-sprint5 -n pd-network-demo run front-end-app --image=nginx:1.27 --labels=role=front-end,app=front-end-app --expose --port=80
kubectl --context=pd-sprint5 -n pd-network-demo run back-end-api-app --image=nginx:1.27 --labels=role=back-end-api,app=back-end-api-app --expose --port=80
kubectl --context=pd-sprint5 -n pd-network-demo run admin-front-end-app --image=nginx:1.27 --labels=role=admin-front-end,app=admin-front-end-app --expose --port=80
kubectl --context=pd-sprint5 -n pd-network-demo run admin-back-end-api-app --image=nginx:1.27 --labels=role=admin-back-end-api,app=admin-back-end-api-app --expose --port=80
kubectl --context=pd-sprint5 -n pd-network-demo wait --for=condition=Ready pod --all --timeout=180s
kubectl --context=pd-sprint5 apply -f Task5/network-policies.yaml
```

Проверка из тестового Pod с соответствующей меткой:

```bash
kubectl --context=pd-sprint5 -n pd-network-demo run test-front --image=busybox:1.36 --labels=role=front-end --restart=Never --command -- sleep 3600
kubectl --context=pd-sprint5 -n pd-network-demo wait --for=condition=Ready pod/test-front --timeout=120s
kubectl --context=pd-sprint5 -n pd-network-demo exec test-front -- wget -qO- -T 3 http://back-end-api-app
kubectl --context=pd-sprint5 -n pd-network-demo exec test-front -- wget -qO- -T 3 http://admin-back-end-api-app
```

Первый `wget` должен вернуть страницу Nginx, второй - завершиться по тайм-ауту. Полную матрицу автоматически выполняет [`test-network-policies.sh`](test-network-policies.sh):

```bash
KUBE_CONTEXT=pd-sprint5 ./Task5/test-network-policies.sh
```

Скрипт создаёт пять временных BusyBox Pod, проверяет десять направлений, печатает Markdown-таблицу, возвращает ненулевой код при расхождении и удаляет тестовые Pod через `trap`. Подмена метки `role` пользователем с правом создавать Pod может обойти такую модель; в продуктиве выдачу меток и создание Pod ограничивает RBAC/admission policy. Сетевые политики работают на сетевом уровне, поэтому авторизация пользователя в API всё равно обязательна.

Метка `app` в командах выше нужна Service: она не даёт ему выбрать тестовый BusyBox Pod с той же меткой `role`. Сетевая политика намеренно использует только `role`.

## Матрица проверки

| Источник | Назначение | Ожидание | Проверенный результат |
| --- | --- | --- | --- |
| `front-end` | `back-end-api` | ALLOW | ALLOW |
| `back-end-api` | `front-end` | ALLOW | ALLOW |
| `admin-front-end` | `admin-back-end-api` | ALLOW | ALLOW |
| `admin-back-end-api` | `admin-front-end` | ALLOW | ALLOW |
| `front-end` | `admin-back-end-api` | DENY | DENY |
| `back-end-api` | `admin-front-end` | DENY | DENY |
| `admin-front-end` | `back-end-api` | DENY | DENY |
| `admin-back-end-api` | `front-end` | DENY | DENY |
| Pod без `role` | `back-end-api` | DENY | DENY |
| Pod без `role` | `admin-back-end-api` | DENY | DENY |

Матрица повторно выполнена 20 сентября 2026 года в профиле `pd-sprint5` с Calico: все десять результатов совпали с ожиданиями. Тестовые Pod удалены автоматически; четыре Nginx Pod и шесть NetworkPolicy оставлены в `pd-network-demo`.

Основа: [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/).
