# Документация модулей AI Talent Camp Infrastructure

> **Последнее обновление:** 2026-03-17
> **Связанные документы:** [architecture.md](architecture.md), [admin-guide.md](admin-guide.md)

## Обзор

Инфраструктура состоит из Terraform модулей для провизионинга и Ansible ролей для конфигурации.

**Terraform модули** (провизионинг VM, сетей, ключей):
```
modules/
├── network/           # Подсети (public + private)
├── security/          # Security groups
├── edge/              # Edge/NAT VM с floating IP
├── team_vm/           # VM для команд
└── team-credentials/  # Управление SSH-ключами и credentials
```

**Ansible роли** (постнастройка серверов):
```
ansible/roles/
├── common/    # Базовые пакеты
├── docker/    # Docker + Docker Compose
├── nat/       # NAT (iptables MASQUERADE + hairpin NAT)
├── traefik/   # Traefik reverse proxy (Docker)
└── xray/      # Xray transparent proxy (systemd)
```

---

## Terraform модули

### Module: network

#### Назначение

Создает публичную и приватную подсети. В Cloud.ru Evolution нет ресурса VPC -- подсети создаются как самостоятельные ресурсы.

#### Ресурсы

- `cloudru_evolution_subnet.public` -- публичная подсеть для edge VM (с `routed_network = true`)
- `cloudru_evolution_subnet.private` -- приватная подсеть для team VMs

#### Входные переменные

| Переменная | Тип | Описание |
|------------|-----|----------|
| `public_cidr` | string | CIDR публичной подсети |
| `private_cidr` | string | CIDR приватной подсети |
| `availability_zone_id` | string | ID зоны доступности |
| `project_name` | string | Имя проекта для именования ресурсов |

#### Outputs

| Output | Описание |
|--------|----------|
| `public_subnet_name` | Имя публичной подсети |
| `private_subnet_name` | Имя приватной подсети |

#### Пример использования

```hcl
module "network" {
  source = "../../modules/network"

  public_cidr          = "10.0.1.0/24"
  private_cidr         = "10.0.2.0/24"
  availability_zone_id = local.az.id
  project_name         = var.project_name
}
```

---

### Module: security

#### Назначение

Создает security groups для edge и team VMs. Правила задаются inline (`rules {}` блоки), источник -- CIDR (`remote_ip_prefix`).

#### Ресурсы

- `cloudru_evolution_security_group.edge` -- SG для edge VM
- `cloudru_evolution_security_group.team` -- SG для team VMs

#### Правила Edge SG

| Направление | Протокол | Порт | Источник |
|-------------|----------|------|----------|
| Ingress | TCP | 22 | 0.0.0.0/0 |
| Ingress | TCP | 80 | 0.0.0.0/0 |
| Ingress | TCP | 443 | 0.0.0.0/0 |
| Ingress | ANY | - | private_cidr |
| Ingress | ICMP | - | 0.0.0.0/0 |
| Egress | ANY | - | 0.0.0.0/0 |

#### Правила Team SG

| Направление | Протокол | Порт | Источник |
|-------------|----------|------|----------|
| Ingress | TCP | 22 | public_cidr |
| Ingress | TCP | 80 | public_cidr |
| Ingress | TCP | 443 | public_cidr |
| Ingress | ANY | - | private_cidr |
| Ingress | ICMP | - | public_cidr |
| Egress | ANY | - | 0.0.0.0/0 |

#### Входные переменные

| Переменная | Тип | Описание |
|------------|-----|----------|
| `name` | string | Базовое имя для ресурсов |
| `public_cidr` | string | CIDR публичной подсети |
| `private_cidr` | string | CIDR приватной подсети |
| `availability_zone_id` | string | ID зоны доступности |

#### Outputs

| Output | Описание |
|--------|----------|
| `edge_sg_id` | ID edge security group |
| `team_sg_id` | ID team security group |

---

### Module: edge

#### Назначение

Создает edge/NAT VM с floating IP и двумя сетевыми интерфейсами (public + private subnet).

#### Ресурсы

- `cloudru_evolution_compute.edge` -- VM instance
- `cloudru_evolution_floatingip.edge` -- Floating IP (публичный адрес)

Все компоненты (Docker, Traefik, Xray, NAT) устанавливаются и настраиваются через Ansible, а не через cloud-init.

#### Входные переменные

| Переменная | Тип | Описание |
|------------|-----|----------|
| `flavor_id` | string | ID типа VM |
| `disk_type_id` | string | ID типа диска |
| `disk_size` | number | Размер диска (GB) |
| `availability_zone_id` | string | ID зоны доступности |
| `availability_zone_name` | string | Имя зоны доступности |
| `public_subnet_name` | string | Имя публичной подсети |
| `private_subnet_name` | string | Имя приватной подсети |
| `security_group_id` | string | ID edge security group |
| `user_name` | string | Username для SSH |
| `public_key` | string | SSH public key (админский) |
| `private_ip` | string | Приватный IP в private subnet |

#### Outputs

| Output | Описание |
|--------|----------|
| `public_ip` | Публичный (floating) IP |
| `private_ip` | Приватный IP |

#### Пример использования

```hcl
module "edge" {
  source = "../../modules/edge"

  flavor_id              = local.edge_flavor.id
  disk_type_id           = local.ssd_disk_type.id
  disk_size              = var.edge_disk_size
  availability_zone_id   = local.az.id
  availability_zone_name = var.availability_zone_name
  public_subnet_name     = module.network.public_subnet_name
  private_subnet_name    = module.network.private_subnet_name
  security_group_id      = module.security.edge_sg_id
  user_name              = var.jump_user
  public_key             = var.jump_public_key
  private_ip             = cidrhost(var.private_cidr, 1)

  depends_on = [module.network, module.security]
}
```

---

### Module: team_vm

#### Назначение

Создает VM для команд в приватной подсети со статическими IP-адресами.

#### Ресурсы

- `cloudru_evolution_compute.team` -- VM instance (for_each по teams)

#### Входные переменные

| Переменная | Тип | Описание |
|------------|-----|----------|
| `teams` | map(object) | Конфигурация команд (user, public_keys, ip) |
| `flavor_id` | string | ID типа VM |
| `disk_type_id` | string | ID типа диска |
| `disk_size` | number | Размер диска (GB) |
| `availability_zone_name` | string | Имя зоны доступности |
| `private_subnet_name` | string | Имя приватной подсети |
| `security_group_id` | string | ID team security group |
| `team_public_keys` | map(string) | Сгенерированные SSH public keys |

#### Outputs

| Output | Описание |
|--------|----------|
| `team_ips` | Map team_id -> private IP |

#### Пример использования

```hcl
module "team_vm" {
  source = "../../modules/team_vm"

  teams                  = var.teams
  flavor_id              = local.team_flavor.id
  disk_type_id           = local.ssd_disk_type.id
  disk_size              = var.team_disk_size
  availability_zone_name = var.availability_zone_name
  private_subnet_name    = module.network.private_subnet_name
  security_group_id      = module.security.team_sg_id

  team_public_keys = {
    for team_id, key in tls_private_key.team_vm_key : team_id => key.public_key_openssh
  }

  depends_on = [module.network, module.security]
}
```

---

### Module: team-credentials

#### Назначение

Управляет SSH ключами команд и генерирует credentials файлы.

#### Ресурсы

- `local_file` -- приватные/публичные ключи для bastion, VM и GitHub
- `local_file` -- готовый SSH конфиг для каждой команды

#### Входные переменные

| Переменная | Тип | Описание |
|------------|-----|----------|
| `teams` | map(object) | Конфигурация команд (user, private_ip) |
| `domain` | string | Базовый домен |
| `jump_user` | string | Username для bastion |
| `bastion_ip` | string | Публичный IP bastion |
| `team_jump_private_keys` | map(string) | Приватные ключи для bastion |
| `team_jump_public_keys` | map(string) | Публичные ключи для bastion |
| `team_vm_private_keys` | map(string) | Приватные ключи для VM |
| `team_vm_public_keys` | map(string) | Публичные ключи для VM |
| `team_github_private_keys` | map(string) | Приватные ключи для GitHub |
| `team_github_public_keys` | map(string) | Публичные ключи для GitHub |

#### Генерируемые файлы

Для каждой команды создаётся папка `secrets/team-<key>/` с файлами:

```
secrets/team-team01/
├── <user>-jump-key          # Приватный ключ для bastion
├── <user>-jump-key.pub      # Публичный ключ для bastion
├── <user>-key               # Приватный ключ для VM
├── <user>-key.pub           # Публичный ключ для VM
├── <user>-deploy-key        # Приватный ключ для GitHub
├── <user>-deploy-key.pub    # Публичный ключ для GitHub
└── ssh-config               # Готовый SSH конфиг
```

---

## Ansible роли

### Role: common

Устанавливает базовые пакеты: curl, wget, htop, jq, unzip, net-tools.

**Применяется к:** edge VM, team VMs

### Role: docker

Устанавливает Docker CE, Docker CLI, containerd и docker-compose-plugin. Добавляет пользователя в группу docker.

**Применяется к:** edge VM, team VMs

### Role: nat

Настраивает edge VM как NAT-шлюз:
- Включает IP forwarding (`net.ipv4.ip_forward=1`)
- Устанавливает iptables-persistent
- Настраивает MASQUERADE для private subnet
- Настраивает hairpin NAT (DNAT + MASQUERADE для обращений из private subnet к публичному IP edge)

**Применяется к:** edge VM

### Role: traefik

Развертывает Traefik reverse proxy как Docker-контейнер:
- Создает директории `/etc/traefik/` и `/etc/traefik/dynamic/`
- Развертывает статическую конфигурацию из Jinja2-шаблона
- Генерирует динамическую конфигурацию для team routing
- Запускает контейнер с `network_mode: host`

**Применяется к:** edge VM

### Role: xray

Устанавливает и настраивает Xray как systemd-сервис для прозрачного проксирования (TPROXY):
- Скачивает Xray-core binary
- Развертывает конфигурацию из Jinja2-шаблона в `/etc/xray/config.json`
- Создает systemd unit
- Включает и запускает сервис

**Применяется к:** edge VM

---

## Диаграмма зависимостей

### Terraform

```
data sources (AZ, flavor, disk_type)
  -> network -> security -> edge  -> team_vm
                                  -> team-credentials
                                  -> ansible inventory
```

### Ansible

```
playbooks/site.yml
  -> playbooks/edge.yml
  |    -> roles: common, docker, nat, traefik, xray
  |
  -> playbooks/team-vms.yml
       -> roles: common, docker
```

## Порядок развертывания

1. **terraform apply** -- создаёт VM, сети, security groups, SSH-ключи, Ansible inventory
2. **ansible-playbook playbooks/edge.yml** -- настраивает edge VM (Docker, NAT, Traefik, Xray)
3. **ansible-playbook playbooks/team-vms.yml** -- настраивает team VMs (базовые пакеты, Docker)

## Генерация ключей (в environments/dev/main.tf)

Для каждой команды автоматически генерируются:

- `tls_private_key.team_jump_key` -- ключ для bastion
- `tls_private_key.team_vm_key` -- ключ для VM команды
- `tls_private_key.team_github_key` -- ключ для GitHub CI/CD

Все ключи сохраняются в `secrets/team-<key>/` вместе с готовым SSH config.

## Ansible Inventory

Inventory автоматически генерируется Terraform из шаблона `ansible/templates/inventory.yml.tpl` и сохраняется в `ansible/inventory/hosts.yml`.
