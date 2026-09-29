# RBAC для Kubernetes

Области `pd-sales`, `pd-housing`, `pd-finance`, `pd-data` повторяют четыре бизнес-домена. Пример запускается в отдельном пустом профиле Minikube `pd-sprint5`; роль и привязка создаются скриптами из этой директории. Пользователи Kubernetes представлены клиентскими X.509-сертификатами с `CN` (пользователь) и `O` (группа). В рабочем контуре вместо ручных сертификатов нужен корпоративный IdP с управляемым отзывом, MFA и коротким сроком сессии.

| Роль | Права роли | Группы пользователей |
| --- | --- | --- |
| `pd-domain-viewer` (ClusterRole, RoleBinding в каждом доменном namespace) | `get/list/watch` workload, Service, ConfigMap, Event, Ingress, NetworkPolicy, ResourceQuota, LimitRange и логов Pod. Нет Secret, RBAC и изменения ресурсов. | Функциональные/операционные команды конкретного домена: `pd:sales:viewers`, `pd:housing:viewers`, `pd:finance:viewers`, `pd:data:viewers`. |
| `pd-domain-deployer` (ClusterRole, RoleBinding только своего namespace) | Создание/изменение/удаление Deployment, StatefulSet, DaemonSet, Job, CronJob, Service, ConfigMap, Ingress; чтение Pod/логов. Не может менять RBAC, Secret, ServiceAccount и namespace. [Admission policy](deployer-admission-policy.yaml) разрешает только `pd-unprivileged` без токена и отклоняет прямые ссылки на Secret и опасные типы томов в PodSpec. Namespace применяет Pod Security `restricted`. | DevOps-инженеры домена: `pd:sales:devops`, `pd:housing:devops`, `pd:finance:devops`, `pd:data:devops`. |
| `pd-cluster-configurator` (ClusterRole + ClusterRoleBinding) | Создание и изменение namespace; настройка ResourceQuota, LimitRange и NetworkPolicy во всех доменах; просмотр узлов. Не может читать Secret, менять RBAC и запускать workload. | Платформенные инженеры `pd:platform:configurators`. |
| `pd-secret-auditor` (ClusterRole, RoleBinding в каждом доменном namespace) | `get/list/watch` Secret и базовых метаданных workload для аудита. Не может изменять Secret или выдавать права. Доступ к содержимому Secret - привилегированный и **должен журналироваться** audit policy рабочего кластера. | Специалист ИБ и назначенные заместители `pd:security:auditors`. |

Сценарии и порядок выполнения:

```bash
KUBE_CONTEXT=pd-sprint5 ./02-create-roles.sh
KUBE_CONTEXT=pd-sprint5 ./03-bind-users.sh
KUBE_CONTEXT=pd-sprint5 ./01-create-users.sh
```

`01-create-users.sh` создаёт четыре примера пользователей, согласует CSR через Kubernetes API и записывает ключи и kubeconfig в игнорируемую Git директорию `Task4/.local-credentials` с правами `0700`. Нужен администратор кластера, `openssl`, `base64`, `kubectl`. Сам Kubernetes не хранит учётные записи пользователей как объекты API: создание пользователя здесь означает выдачу клиентского сертификата и настройку kubeconfig. Срок сертификата определяется настройкой signer кластера; отзыв выполняется через запрет группы/привязки либо замену CA, поэтому для реальной эксплуатации нужен IdP.

`02-create-roles.sh` также применяет две `ValidatingAdmissionPolicy` с действием `Deny` и `failurePolicy: Fail`: общую для операций `CREATE`/`UPDATE` над Pod, Deployment, StatefulSet, DaemonSet, Job и CronJob и отдельную типизированную проверку StatefulSet storage. Политики запрещают Secret volume, Secret в `env`/`envFrom`, `imagePullSecrets`, projected Secret/ServiceAccount token, PVC, generic ephemeral volume, CSI, hostPath, StatefulSet `volumeClaimTemplates`, `hostPort`, привилегированный контейнер и host namespaces. Они требуют `runAsNonRoot`, seccomp `RuntimeDefault`/`Localhost`, `allowPrivilegeEscalation: false`, сброс `ALL` capabilities и разрешают добавить только `NET_BIND_SERVICE`. `03-bind-users.sh` создаёт отдельную ServiceAccount `pd-unprivileged` без автоматического токена и маркирует доменные namespace уровнем Pod Security `restricted` для enforce/audit/warn. Другие ServiceAccount в PodSpec для этих групп отклоняются. Требуется Kubernetes 1.30+ с ValidatingAdmissionPolicy.

Проверка полномочий:

```bash
kubectl --kubeconfig Task4/.local-credentials/pd-sales-viewer.kubeconfig auth can-i list pods -n pd-sales
kubectl --kubeconfig Task4/.local-credentials/pd-sales-viewer.kubeconfig auth can-i get secrets -n pd-sales
kubectl --kubeconfig Task4/.local-credentials/pd-sales-viewer.kubeconfig auth can-i list pods -n pd-housing
kubectl --kubeconfig Task4/.local-credentials/pd-security-auditor.kubeconfig auth can-i get secrets -n pd-housing
kubectl --kubeconfig Task4/.local-credentials/pd-platform-configurator.kubeconfig auth can-i create networkpolicies -n pd-sales
```

Ожидание по строкам: `yes`, `no`, `no`, `yes`, `yes`. Сетевое разделение доменов требует NetworkPolicy и CNI с поддержкой политик.

Проверено в профиле `pd-sprint5`: просмотр Pod в `pd-sales` у `pd-sales-viewer` - `yes`, просмотр Secret и Pod в чужом `pd-housing` - `no`; создание Deployment у `pd-housing-devops` в своём namespace - `yes`, в `pd-sales` - `no`; создание NetworkPolicy у `pd-platform-configurator` - `yes`, чтение Secret - `no`; чтение Secret у `pd-security-auditor` - `yes`, удаление - `no`.

### Проверка обхода через workload

Отрицательный тест от имени доменного DevOps (серверный dry-run выполняет admission без создания Pod):

```bash
kubectl --kubeconfig Task4/.local-credentials/pd-housing-devops.kubeconfig \
  -n pd-housing create --dry-run=server -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: {name: guard-secret-volume}
spec:
  selector: {matchLabels: {app: guard-secret-volume}}
  template:
    metadata: {labels: {app: guard-secret-volume}}
    spec:
      serviceAccountName: pd-unprivileged
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        seccompProfile: {type: RuntimeDefault}
      volumes:
        - name: stolen
          secret: {secretName: finance-token}
      containers:
        - name: nginx
          image: nginx:1.27
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: [ALL]}
          volumeMounts: [{name: stolen, mountPath: /secret}]
YAML
```

Фактический результат в `pd-sprint5`: запрос с Secret отклонён `ValidatingAdmissionPolicy 'pd-deployer-workload-guard'`. Аналогично отклонены Secret в `env.valueFrom.secretKeyRef`, Deployment с `serviceAccountName: default`, PVC, `hostPort`, privileged-контейнер и добавление capability `SYS_ADMIN`; отдельная политика отклонила StatefulSet `volumeClaimTemplates`. Допустимый Deployment с `pd-unprivileged`, `automountServiceAccountToken: false`, профилем Pod Security `restricted` и без ссылок на Secret прошёл серверный dry-run. Обе политики имеют пустой список предупреждений CEL type checking.

### Границы защиты

RBAC вместе с ValidatingAdmissionPolicy и Pod Security `restricted` закрывает проверенные прямые ссылки на Secret/ServiceAccount и типовые опасные настройки PodSpec для группы DevOps. Это **не полная граница доверия**: право создавать произвольный workload позволяет обращаться к доступным по сети API, читать данные самого приложения, влиять на ConfigMap и эксплуатировать уязвимость образа или runtime. Для рабочего контура дополнительно нужны default-deny NetworkPolicy и egress allowlist в каждом namespace, доверенный registry и проверка подписей образов, разделение привилегированных приложений по namespace, runtime security и запрет изменения ConfigMap, которую использует более доверенный workload.

`get/list/watch` Secret у `pd-secret-auditor` возвращает содержимое Secret. Поэтому API-аудит операций с Secret обязателен в рабочем кластере. Этот проект не меняет конфигурацию запуска API server Minikube и не заявляет, что audit policy уже включена; здесь реализованы RBAC и admission-ограничения, а требование логирования явно зафиксировано для промышленного кластера.

Основа: [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/), [RBAC good practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/), [ValidatingAdmissionPolicy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/), [Kubernetes certificates and CSR](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/). Исходный [шаблон таблицы](roles_template.md).
