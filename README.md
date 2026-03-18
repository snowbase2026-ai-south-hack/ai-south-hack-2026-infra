# AI South Hub 2026 — Infrastructure

> Terraform + Ansible инфраструктура для хакатона AI South Hub 2026 на Cloud.ru Evolution

## Что это

Проект создаёт управляемую инфраструктуру для проведения хакатона: виртуальные машины для команд, HTTPS reverse proxy, проксирование AI API.

**Ключевые возможности:**

- **Edge/NAT сервер** — единственная точка входа с публичным IP и floating IP
- **Traefik на edge** (Docker, `network_mode: host`) — HTTPS с автоматическим ACME/Let's Encrypt, маршрутизация по поддомену на VM команды
- **team-traefik на team VM** (Docker) — HTTP-only, docker provider; команды деплоят сервисы через docker labels
- **Xray** (systemd) — прозрачное проксирование AI API через TPROXY
- **Team VMs** — отдельная VM для каждой команды (4 vCPU, 8GB RAM, 65GB SSD)
- **Автоматические credentials** — SSH ключи и setup-скрипты генерируются Terraform

## Архитектура

### Для команд

```
Вы / IDE  ──SSH──►  bastion.south.aitalenthub.ru  ──►  Ваша VM (10.0.1.x)
          ──HTTPS─► {team_id}.south.aitalenthub.ru ──►  team-traefik ──► ваш контейнер
```

**Что у вас есть:**
- Выделенная VM Ubuntu 22.04 (4 vCPU, 8GB RAM, 65GB SSD)
- SSH доступ через bastion (один ключ `{team_id}-key`)
- Домен `{team_id}.south.aitalenthub.ru` с HTTPS (Let's Encrypt)
- Предустановлен Docker + Traefik — деплой через docker labels
- Доступ в интернет и к AI API через Xray

### Для администраторов

Детальная архитектура — [docs/architecture.md](docs/architecture.md)

## Быстрый старт

### Для команд участников

Вы получаете папку `team-{id}/` с SSH ключом и скриптами.

**Mac / Linux:**
```bash
cd ~/Downloads/team-{id}
bash setup.sh
ssh {team_id}
```

**Windows (CMD):**
Двойной клик на `setup.bat`, затем `ssh {team_id}` в любом терминале.

**Windows (PowerShell):**
Правой кнопкой → «Запустить с помощью PowerShell» на `setup.ps1`.

Подробнее — [docs/quickstart.md](docs/quickstart.md)

### Для администраторов

```bash
# 1. Настроить Cloud.ru Evolution credentials
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
# Заполнить project_id, auth_key_id, auth_secret, jump_public_key, teams

# 2. Задеплоить инфраструктуру
terraform init
terraform apply
# Terraform сгенерирует secrets/team-{id}/ для каждой команды

# 3. Создать secrets/admin-keys.txt (SSH публичные ключи администраторов)
echo "ssh-ed25519 AAAA... admin@example.com" > ../../secrets/admin-keys.txt

# 4. Настроить VM через Ansible
cd ../../ansible
ansible-playbook playbooks/edge.yml      # edge: NAT, Traefik, Xray
ansible-playbook playbooks/team-vms.yml  # команды: маршрут, Docker, team-traefik
```

## Работа с доменами

Каждая команда получает поддомен: **`{team_id}.south.aitalenthub.ru`**

Домен настроен автоматически через Traefik на edge VM. SSL сертификат выдаётся Let's Encrypt через HTTP-01 challenge.

Деплой сервиса командой — через docker labels (подробнее [docs/user-guide.md](docs/user-guide.md#деплой-через-traefik)).

## Структура проекта

```
ai-south-hack-2026-infra/
├── modules/
│   ├── network/          # Подсеть 10.0.1.0/24
│   ├── security/         # Security group для team VMs
│   ├── edge/             # Edge/NAT VM
│   ├── team_vm/          # VM для команд
│   └── team-credentials/ # SSH ключи + setup-скрипты
│
├── environments/
│   └── dev/              # Точка входа Terraform
│
├── ansible/
│   ├── playbooks/        # edge.yml, team-vms.yml, sync-keys.yml
│   └── roles/            # common, docker, nat, traefik, team-traefik, xray
│
├── templates/
│   └── team/             # Шаблоны: ssh-config, setup.sh, setup.bat, setup.ps1, README.md
│
├── docs/                 # Документация
│
└── secrets/              # Генерируемые ключи и конфиги (gitignored)
    ├── team-{id}/        # {id}-key, ssh-config, setup.sh, setup.bat, setup.ps1, README.md
    ├── admin-keys.txt    # Публичные ключи администраторов (создать вручную!)
    └── teams-credentials.json
```

## Ресурсы

| Компонент | vCPU | RAM | Disk | Кол-во |
|-----------|------|-----|------|--------|
| Edge VM | 2 | 4GB | 20GB SSD | 1 |
| Team VM | 4 | 8GB | 65GB SSD | По числу команд |

## Документация

### Для команд

| Документ | Описание |
|----------|----------|
| [quickstart.md](docs/quickstart.md) | Подключение к VM и первое приложение |
| [user-guide.md](docs/user-guide.md) | Полное руководство: Docker, Traefik, домены, AI API |

### Для администраторов

| Документ | Описание |
|----------|----------|
| [admin-guide.md](docs/admin-guide.md) | Развёртывание и управление инфраструктурой |
| [architecture.md](docs/architecture.md) | Детальная архитектура |
| [modules.md](docs/modules.md) | Документация Terraform модулей |

## Технологии

- **IaC:** Terraform (Cloud.ru Evolution provider v1.6.0)
- **Cloud:** Cloud.ru Evolution
- **OS:** Ubuntu 22.04 LTS
- **Reverse Proxy:** Traefik v3 (Docker)
- **Transparent Proxy:** Xray (systemd)
- **Automation:** Ansible
