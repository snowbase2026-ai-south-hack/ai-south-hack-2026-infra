# Документация модулей AI South Hub 2026 Infrastructure

> **Последнее обновление:** 2026-03-17
> **Связанные документы:** [architecture.md](architecture.md), [admin-guide.md](admin-guide.md)

## Обзор

Инфраструктура состоит из Terraform модулей для провизионинга и Ansible ролей для конфигурации.

**Terraform модули** (провизионинг VM, сетей, ключей):
```
modules/
├── network/           # Единственная подсеть (10.0.1.0/24)
├── security/          # Security groups
├── edge/              # Edge/NAT VM с floating IP
├── team_vm/           # VM для команд
└── team-credentials/  # Управление SSH-ключами и credentials
```

**Ansible роли** (постнастройка серверов):
```
ansible/roles/
├── common/        # Базовые пакеты, Node.js, uv, Claude Code, Playwright
├── docker/        # Docker + Docker Compose
├── nat/           # NAT (iptables MASQUERADE + hairpin NAT)
├── traefik/       # Traefik reverse proxy (Docker, edge)
├── team-traefik/  # HTTP-only Traefik (Docker, team VMs)
└── xray/          # Xray transparent proxy (systemd)
```

---

## Terraform модули

### Module: network

#### Назначение

Создает единственную подсеть (10.0.1.0/24) для edge VM и team VMs. В Cloud.ru Evolution нет ресурса VPC -- подсети создаются как самостоятельные ресурсы.

#### Ресурсы

- `cloudru_evolution_subnet.main` -- подсеть для всех VM (edge + teams), `routed_network = true`

#### Входные переменные

| Переменная | Тип | Описание |
|------------|-----|----------|
| `subnet_cidr` | string | CIDR единственной подсети (default: 10.0.1.0/24) |
| `availability_zone_id` | string | ID зоны доступности |
| `project_name` | string | Имя проекта для именования ресурсов |

#### Outputs

| Output | Описание |
|--------|----------|
| `subnet_name` | Имя подсети |

#### Пример использования

```hcl
module "network" {
  source = "../../modules/network"

  subnet_cidr          = "10.0.1.0/24"
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

> **Примечание:** Edge VM не имеет security group (`interface_security_enabled=false`) — firewall через iptables.

#### Правила Team SG (team VMs)

| Направление | Протокол | Порт | Источник |
|-------------|----------|------|----------|
| Ingress | TCP | 22 | edge_ip/32 |
| Ingress | TCP | 80 | edge_ip/32 |
| Ingress | TCP | 443 | edge_ip/32 |
| Ingress | ANY | - | subnet_cidr |
| Egress | ANY | - | 0.0.0.0/0 |

#### Входные переменные

| Переменная | Тип | Описание |
|------------|-----|----------|
| `name` | string | Базовое имя для ресурсов |
| `subnet_cidr` | string | CIDR подсети (10.0.1.0/24) |
| `edge_private_ip` | string | IP edge VM для правил SG |
| `availability_zone_id` | string | ID зоны доступности |

#### Outputs

| Output | Описание |
|--------|----------|
| `edge_sg_id` | ID edge security group |
| `team_sg_id` | ID team security group |

---

### Module: edge

#### Назначение

Создает edge/NAT VM с floating IP. Один сетевой интерфейс (`interface_security_enabled=false`), статический IP 10.0.1.10.

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
| `subnet_name` | string | Имя подсети |
| `security_group_id` | string | ID security group |
| `ip_address` | string | Статический IP (default: 10.0.1.10) |
| `user_name` | string | Username для SSH |
| `public_key` | string | SSH public key (админский) |

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
  subnet_name            = module.network.subnet_name
  security_group_id      = module.security.edge_sg_id
  ip_address             = cidrhost(var.subnet_cidr, 10)
  user_name              = var.jump_user
  public_key             = var.jump_public_key

  depends_on = [module.network, module.security]
}
```

---

### Module: team_vm

#### Назначение

Создает VM для команд в единственной подсети со статическими IP-адресами (задаются в `teams.ip`).

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
| `subnet_name` | string | Имя подсети |
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
  subnet_name            = module.network.subnet_name
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

- `local_file` -- приватный и публичный SSH ключ для каждой команды
- `local_file` -- готовый SSH конфиг для каждой команды
- `local_file` -- установочные скрипты (setup.sh, setup.bat, setup.ps1) и README.md
- `local_file` -- сводный JSON `secrets/teams-credentials.json`

#### Входные переменные

| Переменная | Тип | Описание |
|------------|-----|----------|
| `teams` | map(object) | Конфигурация команд (user, private_ip) |
| `domain` | string | Базовый домен |
| `jump_user` | string | Username для bastion |
| `bastion_ip` | string | Публичный IP bastion |
| `team_private_keys` | map(string) | Приватные SSH ключи (по одному на команду) |
| `team_public_keys` | map(string) | Публичные SSH ключи (по одному на команду) |

#### Генерируемые файлы

Для каждой команды создаётся папка `secrets/team-{team_id}/` с файлами:

```
secrets/team-dashboard/
├── dashboard-key        # Приватный SSH ключ (для bastion и VM)
├── dashboard-key.pub    # Публичный ключ
├── ssh-config           # Готовый SSH конфиг
├── setup.sh             # Установочный скрипт (Linux/macOS)
├── setup.bat            # Установочный скрипт (Windows CMD)
├── setup.ps1            # Установочный скрипт (PowerShell, UTF-8 BOM)
└── README.md            # Инструкция для команды
```

Плюс сводный файл: `secrets/teams-credentials.json`

---

## Ansible роли

### Role: common

Устанавливает базовые пакеты (curl, wget, btop, htop, bat, ripgrep, fd-find, jq, tmux, tree, ncdu и др.), настраивает `.bashrc` с алиасами и nvm. Устанавливает Node.js LTS (через nvm), uv (Python package manager). На team VMs дополнительно: Claude Code и Playwright+Chromium. Docker устанавливается отдельной ролью `docker`.

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

### Role: team-traefik

Развертывает HTTP-only Traefik как Docker-контейнер на team VM:
- Создает Docker-сеть `traefik`
- Создает директорию `/etc/traefik/`
- Развертывает статическую конфигурацию из Jinja2-шаблона
- Запускает контейнер с портом 80, docker provider — автоматически обнаруживает сервисы команды по Docker labels

**Применяется к:** team VMs

---

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
       -> roles: common, docker, team-traefik
```

## Порядок развертывания

1. **terraform apply** -- создаёт VM, сети, security groups, SSH-ключи, Ansible inventory
2. **ansible-playbook playbooks/edge.yml** -- настраивает edge VM (Docker, NAT, Traefik, Xray)
3. **ansible-playbook playbooks/team-vms.yml** -- настраивает team VMs (базовые пакеты, Docker)

## Генерация ключей (в environments/dev/main.tf)

Для каждой команды автоматически генерируется один ED25519-ключ:

- `tls_private_key.team_key[team_id]` -- ключ для bastion (с ограничением `permitopen`) и для входа на VM

Ключ сохраняется в `secrets/team-{team_id}/` вместе с готовым SSH конфигом и скриптами.

## Ansible Inventory

Inventory автоматически генерируется Terraform из шаблона `ansible/templates/inventory.yml.tpl` и сохраняется в `ansible/inventory/hosts.yml`.
