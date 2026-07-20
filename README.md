# Cloud Infrastructure as Code (Selectel / OpenStack)

Данный проект автоматизирует развертывание гео-распределенной облачной инфраструктуры в дата-центре Selectel на базе платформы OpenStack с использованием инструмента декларативного управления Terraform.

## Архитектура сети и топология
Инфраструктура спроектирована по стандартам безопасности закрытого контура (Private Cluster Topology):
* **Регион:** ru-2 (Москва).
* **Сетевой контур:** Изолированная приватная сеть Neutron (192.168.10.0/24) с виртуальным роутером и NAT-шлюзом для безопасного выхода нод в интернет.
* **Сетевые порты:** Подключение серверов к сети вынесено на уровень независимых портов (`openstack_networking_port_v2`), что позволяет динамически управлять файрволом без перезагрузки инстансов.
* **Файрвол (Security Groups):** Настроена жесткая фильтрация входящего трафика (ingress). Открыты порты: 22 (SSH), 5432 (PostgreSQL), 6443 (Kubernetes API), 10250 (Kubelet) и диапазоны портов NodePort для сервисов кластера. Конфигурация портов описана в файле [main.tf](https://github.com/EvgenKli/my-infrastructure-iac-project/blob/main/main.tf).

## Состав инфраструктуры
1. **msk-backend-node** — Выделенный сервер базы данных и систем мониторинга (1 vCPU, 2 ГБ RAM).
2. **msk-k8s-master** — Управляющая нода кластера Kubernetes / Control Plane (2 vCPU, 4 ГБ RAM, IP: `5.35.28.230`).
3. **spb-k8s-worker** — Рабочая нода кластера Kubernetes в изолированном контуре без публичного IP (2 vCPU, 4 ГБ RAM, зона отказоустойчивости ru-2b).

## Связанные компоненты экосистемы
* Автоматизация ОС, СУБД и Helm: [my-ansible-automation](https://github.com/EvgenKli/my-ansible-automation)
* Исходный код микросервиса и CI/CD конвейер: [my-spring-backend](https://github.com/EvgenKli/my-spring-backend)

## Инструкция по запуску
1. Убедитесь, что файл `secret.tfvars` с вашими API-токенами заполнен и добавлен в `.gitignore`.
2. Инициализируйте провайдеры:
```bash
terraform init
```
3. Проверьте план конфигурации:
```bash
terraform plan -var-file="secret.tfvars"
```
4. Разверните инфраструктуру в облаке:
```bash
terraform apply -var-file="secret.tfvars"
```
