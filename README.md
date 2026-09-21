# PropDevelopment — проект по безопасности данных и интеграций

| Задание | Результат |
| --- | --- |
| 1 | [Mindmap классификации данных и рисков](Task1/data-security-mindmap.drawio), [методика оценки](Task1/README.md) |
| 2 | [Проверочный лист бизнес-систем](Task2/business-systems-checklist.md) |
| 3 | [C4 контекст](Task3/smart-access-context.drawio), [дополненная C4 диаграмма контейнеров](Task3/PropDevelopment_smart-access.drawio), [требования к партнёру](Task3/integration-requirements.md) |
| 4 | [Таблица RBAC и порядок проверки](Task4/roles.md), три исполняемых скрипта `01-create-users.sh`, `02-create-roles.sh`, `03-bind-users.sh`, [admission policy](Task4/deployer-admission-policy.yaml) |
| 5 | [NetworkPolicy](Task5/network-policies.yaml), [запуск и матрица проверки](Task5/README.md), [автоматический тест](Task5/test-network-policies.sh) |

Исходные шаблоны заданий 2 и 4 и исходная C4-диаграмма сохранены рядом с решениями. Файлы `.drawio` открываются в diagrams.net. Для практической проверки заданий 4 и 5 используется отдельный профиль Minikube `pd-sprint5` с Calico. Локальные сертификаты тестовых пользователей остаются в `Task4/.local-credentials/` и исключены из Git.
# architecture-propdevelopment
