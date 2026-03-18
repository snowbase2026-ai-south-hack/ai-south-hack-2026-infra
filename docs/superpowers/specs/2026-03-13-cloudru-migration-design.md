# Миграция инфраструктуры хакатона с Yandex Cloud на Cloud.ru Evolution

**Дата:** 2026-03-13
**Статус:** Утверждён

## Контекст

Существующий репозиторий содержит Terraform-инфраструктуру для хакатона AI Talent Camp на Yandex Cloud. Необходимо адаптировать его для нового хакатона на платформе Cloud.ru Evolution с дополнительными требованиями: предустановка Docker на team VM, hairpin NAT, Ansible для post-deploy конфигурации, возможность массового обновления ПО.

## Требования

### Инфраструктура
- **Платформа:** Cloud.ru Evolution (полный переход, Yandex Cloud удаляется)
- **Terraform-провайдер:** `evo-terraform` v1.6.0 (`cloud.ru/cloudru/cloud`), установка через file system mirror
- **VM:** 12 команд + 1 тестовая + 1 организаторская = 14 team VM + 1 edge VM
- **Ресурсы team VM:** 4 vCPU / 8 GB RAM / 65 GB SSD
- **Ресурсы edge VM:** 2 vCPU / 4 GB RAM / 20 GB SSD (Traefik + Xray + NAT для 14 VM)
- **Домен:** `south.aitalenthub.ru`, поддомены `teamXX.south.aitalenthub.ru`

### Сеть
- Двухуровневая архитектура: edge VM (публичный FIP) + приватные team VM (без FIP)
- Edge VM: Traefik (HTTP/HTTPS reverse proxy) + Xray/TPROXY (AI API proxy) + NAT/MASQUERADE
- Hairpin NAT на edge VM для доступности внутренних сервисов по публичным доменам из приватной подсети
- Маршрутизация: static route в cloud-init team VM (`default via <edge_private_ip>`), без route table (отсутствует в evo-terraform)

### Управление конфигурацией
- **Terraform:** только инфраструктура (VM, сети, security groups, SSH-ключи)
- **Ansible:** вся post-deploy конфигурация (edge: Traefik/Xray/SSH, team VM: Docker-сервисы)
- Terraform генерирует Ansible inventory из outputs
- Ansible подключается через bastion (ProxyJump через edge VM)

### Софт на team VM
- Предустановка через cloud-init: Docker + Docker Compose plugin
- Дополнительные сервисы (Dify, N8N и др.) — через Ansible playbooks, набор определится позже

## Архитектура

### Связность подсетей в Cloud.ru Evolution

В Cloud.ru Evolution нет отдельного ресурса VPC. Подсети создаются как top-level ресурсы в рамках проекта. Подсети в одной availability zone и проекте могут маршрутизировать трафик между собой. Edge VM подключается к обеим подсетям (public и private) через два сетевых интерфейса (`network_interfaces`), что обеспечивает связность и позволяет edge VM выступать шлюзом для приватной подсети.

Если платформа не поддерживает два интерфейса на одной VM — fallback: обе VM в одной подсети с разными security groups, edge VM с FIP.

### IP-адресация

Team VM получают **статические IP-адреса**, заданные в compute resource через `network_interfaces.ip_address`. Это необходимо для:
- Traefik dynamic config (маршруты к конкретным IP)
- Ansible inventory (детерминированные адреса)
- Static route на team VM (default gw → edge private IP)

Схема адресации:
- Edge VM: `10.0.1.10` (public subnet), `10.0.2.1` (private subnet — gateway)
- Team VM: `10.0.2.{10 + team_number}` (team-01 → .11, team-12 → .22)
- Test VM: `10.0.2.100`
- Orga VM: `10.0.2.101`

IP вычисляется в Terraform: `cidrhost(var.private_cidr, 10 + parseint(each.key, 10))` для числовых team ID, и статические значения для `test`/`orga`.

### Сетевая топология

```
Internet
    │
    ▼
┌──────────────────────────────────┐
│  Edge VM (FIP: x.x.x.x)         │
│  Подсеть: public (10.0.1.0/24)  │
│                                  │
│  Traefik :80/:443                │
│  Xray TPROXY :12345              │
│  NAT (MASQUERADE 10.0.2.0/24)   │
│  Hairpin NAT                     │
│  SSH bastion                     │
└──────────┬───────────────────────┘
           │ (маршрутизация)
           ▼
┌──────────────────────────────────┐
│  Приватная подсеть (10.0.2.0/24) │
│                                  │
│  team-01 VM (10.0.2.11)         │
│  team-02 VM (10.0.2.12)         │
│  ...                             │
│  team-12 VM (10.0.2.22)         │
│  test VM   (10.0.2.100)         │
│  orga VM   (10.0.2.101)         │
│                                  │
│  default gw → edge VM            │
└──────────────────────────────────┘
```

### Traefik маршрутизация

- SNI-based TLS passthrough: `teamXX.south.aitalenthub.ru` → team VM :443
- Host-based HTTP routing: `teamXX.south.aitalenthub.ru` → team VM :80
- Wildcard fallback для немаршрутизированных запросов

### Xray/TPROXY

- Прозрачный прокси для AI API (OpenAI, Anthropic и др.)
- VLESS outbound с Reality encryption
- BitTorrent блокировка
- Приватные IP → direct

### Hairpin NAT

Правила iptables на edge VM, чтобы трафик из приватной подсети (10.0.2.0/24) к публичному IP edge VM корректно маршрутизировался обратно. Необходимо для:
- Доступности дашбордов организаторов с team VM
- Межкомандного взаимодействия через публичные домены

```bash
# Hairpin NAT: трафик из приватной подсети к публичному IP возвращается через edge
iptables -t nat -A PREROUTING -s 10.0.2.0/24 -d <EDGE_PUBLIC_IP> -j DNAT --to-destination <EDGE_PRIVATE_IP>
iptables -t nat -A POSTROUTING -s 10.0.2.0/24 -d <EDGE_PRIVATE_IP> -j MASQUERADE
```

## Модульная структура Terraform

```
modules/
├── network/          # 2 подсети (public + private)
│   ├── main.tf       # cloudru_evolution_subnet x2
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
│
├── security/         # 2 security groups
│   ├── main.tf       # edge-sg (SSH/HTTP/HTTPS open) + team-sg (edge-only)
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
│
├── edge/             # Edge/NAT VM
│   ├── main.tf       # cloudru_evolution_compute + cloudru_evolution_fip
│   ├── cloud-init.tpl
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
│
├── team_vm/          # Per-team VM (for_each)
│   ├── main.tf       # cloudru_evolution_compute
│   ├── cloud-init.tpl
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
│
└── team-credentials/ # SSH ключи (без изменений, не зависит от провайдера)
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── versions.tf
```

**Удалённые модули:**
- `routing` — нет route table в evo-terraform, маршрутизация через cloud-init
- `config-sync` — заменён Ansible

**Примечание:** В текущей Yandex Cloud конфигурации private subnet создаётся отдельно от network модуля из-за циклической зависимости (subnet → route table → edge VM → subnet). С удалением route table эта зависимость исчезает, поэтому обе подсети теперь создаются в network модуле.

### Ресурсы Cloud.ru Evolution

| Terraform ресурс | Назначение |
|---|---|
| `cloudru_evolution_subnet` | Подсети (public, private) |
| `cloudru_evolution_security_group` | Security groups с inline rules (source — CIDR, не SG ID) |
| `cloudru_evolution_compute` | VM (edge, team) |
| `cloudru_evolution_fip` | Публичный IP для edge VM |
| `cloudru_evolution_public_key` | SSH public key (опционально, ключи также передаются inline в compute) |

### Провайдер

```hcl
terraform {
  required_providers {
    cloudru = {
      source  = "cloud.ru/cloudru/cloud"
      version = "1.6.0"
    }
  }
}

provider "cloudru" {
  project_id         = var.project_id
  auth_key_id        = var.auth_key_id
  auth_secret        = var.auth_secret
  evolution_endpoint = "https://compute.api.cloud.ru"
}
```

**Аутентификация:** `auth_key_id` + `auth_secret` из сервисного аккаунта Cloud.ru (вместо `secrets/key.json` для Yandex Cloud). Рекомендуется передавать через переменные окружения (`TF_VAR_auth_key_id`, `TF_VAR_auth_secret`) чтобы избежать случайного коммита в `terraform.tfvars`.

### Особенности evo-terraform

- Нет VPC ресурса — подсети создаются напрямую
- Нет Route Table ресурса — маршрутизация через cloud-init static routes
- Все ресурсы требуют `availability_zone` блок — query через `data "cloudru_evolution_availability_zone"`, затем фильтрация по имени (например `"ru.AZ-1"`)
- Security group rules — inline (не отдельные ресурсы), source указывается через `remote_ip_prefix` (CIDR), ссылки на другие SG не поддерживаются → team-sg использует CIDR подсети edge
- Boot disk — inline в compute resource
- Image config (hostname, username, public_key) — inline в compute resource
- Subnet name: минимум 7 символов
- Port ranges в security groups: формат `"from:to"` или `"any"`

## Cloud-init шаблоны

### Edge VM (`modules/edge/cloud-init.tpl`)

Основа сохраняется из текущей конфигурации:
- Установка: `docker.io`, `docker-compose`, `iptables-persistent`, `curl`, `wget`, `htop`, `jq`
- Traefik v3 в Docker (порты 80/443)
- Xray (systemd, TPROXY на порту 12345)
- iptables: MASQUERADE для 10.0.2.0/24, TPROXY mangle rules, policy routing (fwmark=1)
- **Новое:** hairpin NAT правила
- **Изменение:** детекция сетевого интерфейса (может быть не `eth0` на Cloud.ru)

### Team VM (`modules/team_vm/cloud-init.tpl`)

Расширяем текущий минимальный шаблон:
- Создание пользователя + SSH authorized_keys
- Установка Docker + Docker Compose plugin
- Static route: `ip route replace default via ${edge_private_ip}`
- Создание workspace директории
- Подготовка директории `/opt/services/` для будущих Docker Compose стеков
- DNS: используется стандартный DNS от Cloud.ru. Xray перехватывает трафик на уровне IP (TPROXY), отдельная DNS-конфигурация на team VM не требуется

## Ansible

### Структура

```
ansible/
├── ansible.cfg
├── inventory/
│   └── hosts.yml           # генерируется Terraform (terraform output → template)
├── playbooks/
│   ├── site.yml            # мастер-playbook
│   ├── edge.yml            # конфигурация edge VM (роли: traefik, xray, ssh-keys)
│   ├── team-vms.yml        # конфигурация team VM (роли: common, dify, n8n)
│   └── update-services.yml # обновление конфигов/версий (без пересоздания VM)
├── roles/
│   ├── traefik/            # Traefik конфиг + перезапуск
│   ├── xray/               # Xray конфиг + перезапуск
│   ├── dify/               # Dify Docker Compose стек (когда понадобится)
│   ├── n8n/                # N8N Docker Compose стек (когда понадобится)
│   └── common/             # Общие задачи (обновления, мониторинг)
├── group_vars/
│   ├── all.yml             # общие переменные (домен, подсети)
│   ├── edge.yml            # edge-специфичные переменные
│   └── team_vms.yml        # team VM переменные
└── templates/
    ├── traefik/
    │   ├── traefik.yml.j2
    │   └── dynamic.yml.j2
    ├── xray/
    │   └── config.json.j2
    └── docker-compose/
        ├── dify.yml.j2
        └── n8n.yml.j2
```

### Генерация Inventory

Terraform создаёт файл `ansible/inventory/hosts.yml` через ресурс `local_file` с `templatefile()` в `environments/dev/main.tf`. Файл генерируется автоматически при `terraform apply` из outputs (IP-адреса, имена пользователей, team ID).

### Формат Inventory

```yaml
all:
  children:
    edge:
      hosts:
        edge-vm:
          ansible_host: <edge_public_ip>
          ansible_user: ubuntu
          private_ip: <edge_private_ip>
    team_vms:
      hosts:
        team-01:
          ansible_host: <team_01_private_ip>
          ansible_user: team01
          team_id: "01"
        # ... остальные команды
      vars:
        ansible_ssh_common_args: '-o ProxyJump=jump@<edge_public_ip>'
```

### Рабочий процесс

```
1. terraform apply               → создаёт VM + автоматически генерирует Ansible inventory
2. ansible-playbook edge.yml     → конфигурирует edge VM (Traefik, Xray, SSH)
3. ansible-playbook team-vms.yml → конфигурирует team VM (Docker-сервисы)
```

**Добавление новой команды:**
```
1. Добавить запись в terraform.tfvars teams map
2. terraform apply              → новая VM + обновлённый inventory
3. ansible-playbook edge.yml    → обновить Traefik routes + SSH keys
4. ansible-playbook team-vms.yml --limit team-XX  → настроить новую VM
```

**Обновление ПО на всех VM:**
```
ansible-playbook update-services.yml  → обновляет Docker Compose стеки на всех team VM
```

## Teams map (terraform.tfvars)

```hcl
project_id  = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
domain      = "south.aitalenthub.ru"
public_cidr  = "10.0.1.0/24"
private_cidr = "10.0.2.0/24"

teams = {
  "01" = { user = "team01", public_keys = [] }
  "02" = { user = "team02", public_keys = [] }
  "03" = { user = "team03", public_keys = [] }
  "04" = { user = "team04", public_keys = [] }
  "05" = { user = "team05", public_keys = [] }
  "06" = { user = "team06", public_keys = [] }
  "07" = { user = "team07", public_keys = [] }
  "08" = { user = "team08", public_keys = [] }
  "09" = { user = "team09", public_keys = [] }
  "10" = { user = "team10", public_keys = [] }
  "11" = { user = "team11", public_keys = [] }
  "12" = { user = "team12", public_keys = [] }
  "test" = { user = "test", public_keys = [] }
  "orga" = { user = "orga", public_keys = [] }
}
```

## Миграция Terraform state

Начинаем с чистого state. Текущий state ссылается на ресурсы Yandex Cloud, которые не переносятся. Старый state архивируется, импорт из Yandex Cloud не выполняется. Переменная `folder_id` переименовывается в `project_id`.

## Риски и митигации

| Риск | Вероятность | Митигация |
|------|------------|-----------|
| evo-terraform в бете, возможны баги | Средняя | Инфра создаётся один раз; при критических багах — fallback: создать VM вручную в консоли Cloud.ru (15 VM), затем Ansible для всей конфигурации. Ansible playbooks работают независимо от способа создания VM |
| Нет route table — маршрутизация через cloud-init | Низкая | Static routes надёжны; edge VM NAT работает на уровне подсети |
| Cloud.ru может изменить API endpoints | Низкая | Провайдер абстрагирует API; обновление провайдера при необходимости |
| Ресурсов 4 vCPU/8 GB может не хватить с Dify+N8N | Средняя | Мониторить нагрузку; ресурсы параметризованы, легко увеличить |

## Что НЕ входит в скоуп

- Managed Kubernetes (используем простые VM)
- CI/CD pipeline для Terraform/Ansible
- Мониторинг и алертинг (можно добавить позже через Ansible)
- Автоматическое управление DNS (записи создаются вручную)
- Backup стратегия для team VM данных
