# Руководство разработчика

> **Последнее обновление:** 2026-03-17
> **Связанные документы:** [modules.md](modules.md), [changelog.md](changelog.md)

## Обзор

Это руководство для контрибьюторов и разработчиков, работающих с AI South Hub 2026 Infrastructure.

---

## Содержание

- [Структура проекта](#структура-проекта)
- [Стандарты кодирования](#стандарты-кодирования)
- [Разработка модулей](#разработка-модулей)
- [Тестирование](#тестирование)
- [Процесс contribution](#процесс-contribution)
- [Обновление документации](#обновление-документации)

---

## Структура проекта

```
ai-south-hack-2026-infra/
├── modules/                    # Terraform модули
│   ├── network/               # Единая подсеть 10.0.1.0/24
│   ├── security/              # Security groups
│   ├── edge/                  # Edge/NAT VM с floating IP
│   ├── team_vm/               # VM для команд
│   └── team-credentials/      # Управление credentials
│
├── environments/              # Окружения
│   └── dev/                  # Development environment
│       ├── main.tf           # Основная конфигурация
│       ├── variables.tf      # Переменные
│       ├── outputs.tf        # Outputs
│       └── credentials.tf    # Credentials management
│
├── ansible/                   # Ansible конфигурация
│   ├── ansible.cfg           # Конфигурация ansible-core 2.20+
│   ├── playbooks/            # site.yml, edge.yml, team-vms.yml
│   ├── roles/                # common, docker, nat, traefik, xray
│   ├── group_vars/           # all.yml, edge.yml, team_vms.yml
│   ├── inventory/            # hosts.yml (генерируется Terraform)
│   └── templates/            # inventory.yml.tpl (Terraform templatefile)
│
├── docs/                      # Документация
│   ├── quickstart.md         # Быстрый старт
│   ├── architecture.md       # Архитектура
│   ├── admin-guide.md        # Руководство администратора
│   ├── user-guide.md         # Руководство пользователя
│   ├── modules.md            # Документация модулей
│   ├── changelog.md          # История изменений
│   └── development.md        # Это руководство
│
├── secrets/                   # Gitignored - генерируемые ключи
│   ├── team-{id}/             # Папка каждой команды
│   │   ├── {id}-key           # Приватный SSH ключ
│   │   ├── {id}-key.pub       # Публичный ключ
│   │   ├── ssh-config         # Готовый SSH конфиг
│   │   ├── setup.sh / setup.bat / setup.ps1
│   │   └── README.md
│   ├── teams-credentials.json # Сводный JSON всех команд
│   ├── xray-config.json       # Кладётся вручную перед деплоем
│   └── admin-keys.txt         # Публичные ключи администраторов
│
├── CLAUDE.md                  # Инструкции для Claude Code
├── .gitignore
└── README.md                  # Главная страница
```

---

## Стандарты кодирования

### Terraform

#### Форматирование

```bash
# Всегда форматировать перед commit
terraform fmt -recursive
```

#### Naming conventions

**Resources:**
```hcl
# Pattern: <type>_<name>
resource "cloudru_evolution_compute" "edge" { }
resource "cloudru_evolution_subnet" "public" { }
resource "local_file" "team_ssh_config" { }
```

**Variables:**
```hcl
# Используйте snake_case
variable "team_cores" { }
variable "public_subnet_name" { }
```

**Modules:**
```hcl
# Используйте kebab-case для директорий модулей
module "team_credentials" {
  source = "../../modules/team-credentials"
}
```

#### Комментарии

```hcl
# Хорошо: Объясняет "почему"
# Edge VM в единой подсети 10.0.1.0/24, NAT через iptables MASQUERADE
resource "cloudru_evolution_compute" "edge" {
  # ...
}

# Плохо: Описывает "что" (очевидно из кода)
# Создать edge VM
resource "cloudru_evolution_compute" "edge" {
  # ...
}
```

#### Variables

```hcl
variable "example" {
  description = "Clear description of purpose"
  type        = string
  default     = "value"  # Если не требуется - не указывать default

  validation {
    condition     = length(var.example) > 0
    error_message = "Example must not be empty."
  }
}
```

#### Outputs

```hcl
output "example" {
  description = "Clear description of what this outputs"
  value       = resource.type.name.attribute
  sensitive   = false  # true для секретов
}
```

### Ansible

#### Naming conventions

- Роли: snake_case (`common`, `docker`, `nat`)
- Переменные: snake_case (`traefik_version`, `private_cidr`)
- Шаблоны: `*.j2` (Jinja2)
- Handlers: описательные имена (`restart traefik`, `reload systemd`)

#### Структура роли

```
roles/role-name/
├── tasks/main.yml       # Основные задачи
├── templates/*.j2       # Jinja2 шаблоны
├── handlers/main.yml    # Handlers
├── defaults/main.yml    # Значения по умолчанию
└── vars/main.yml        # Переменные роли
```

---

## Разработка модулей

### Структура Terraform модуля

Каждый модуль должен содержать:

```
module-name/
├── main.tf           # Основные ресурсы
├── variables.tf      # Входные переменные
├── outputs.tf        # Outputs
└── versions.tf       # Provider versions
```

### Принципы

1. **Single Responsibility** -- модуль должен решать одну задачу
2. **Reusable** -- модуль должен быть переиспользуемым
3. **Well-documented** -- clear variables и outputs
4. **Tested** -- проверен на работоспособность

### Разработка Ansible ролей

При создании новой Ansible роли:

1. Создать структуру:
   ```bash
   mkdir -p ansible/roles/my-role/{tasks,templates,handlers,defaults}
   touch ansible/roles/my-role/tasks/main.yml
   ```

2. Добавить роль в соответствующий playbook (`edge.yml` или `team-vms.yml`)

3. Определить переменные в `group_vars/`

---

## Тестирование

### Manual Testing

```bash
cd environments/dev

# 1. Проверить форматирование
terraform fmt -check -recursive

# 2. Валидация
terraform init
terraform validate

# 3. Plan (без изменений)
terraform plan

# 4. Применить
terraform apply

# 5. Настроить через Ansible
cd ../../ansible
ansible-playbook playbooks/site.yml

# 6. Проверить работоспособность
# - SSH подключение
# - HTTP/HTTPS routing
# - Xray proxy
# - NAT

# 7. Cleanup
cd ../environments/dev
terraform destroy
```

### Testing Checklist

- [ ] `terraform fmt -check` проходит
- [ ] `terraform validate` проходит
- [ ] `terraform plan` не показывает неожиданных изменений
- [ ] Ansible playbooks выполняются без ошибок
- [ ] SSH подключение работает
- [ ] Интернет работает на team VM
- [ ] TPROXY работает (AI API доступны)
- [ ] Traefik routing работает
- [ ] Документация обновлена

---

## Процесс contribution

### Workflow

```
1. Fork репозитория
     |
2. Создать feature branch
     |
3. Внести изменения
     |
4. Тестировать
     |
5. Commit с хорошим message
     |
6. Push и создать Pull Request
     |
7. Code review
     |
8. Merge
```

### Branch Naming

```
feature/add-monitoring       # Новая функция
fix/edge-vm-networking       # Исправление бага
docs/update-quickstart       # Обновление документации
refactor/simplify-modules    # Рефакторинг
```

### Commit Messages

**Формат:**
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: новая функция
- `fix`: исправление бага
- `docs`: изменения в документации
- `style`: форматирование (не влияет на код)
- `refactor`: рефакторинг кода
- `test`: добавление тестов
- `chore`: обновление build процесса и т.д.

**Примеры:**
```
feat(edge): add monitoring dashboard

Добавлен monitoring dashboard для edge VM.
Отображает CPU, RAM, network traffic.

Closes #42

---

fix(xray): add proxy server IP to TPROXY exclusions

Исправлена проблема петли маршрутизации когда proxy IP
не был исключен из TPROXY.

Fixes #56

---

refactor: migrate to Cloud.ru Evolution provider, add Ansible
```

### Pull Request

**Checklist:**
- [ ] Код отформатирован (`terraform fmt`)
- [ ] Тесты пройдены
- [ ] Ansible playbooks проверены
- [ ] Документация обновлена
- [ ] CHANGELOG.md обновлен (для feature/fix)
- [ ] PR description описывает изменения

---

## Обновление документации

### Принципы

1. **Single Source of Truth** -- каждый факт описан в одном месте
2. **Up-to-date** -- документация обновляется вместе с кодом
3. **Clear** -- понятно для целевой аудитории
4. **Actionable** -- содержит практические примеры
5. **На русском языке** -- вся документация пишется на русском

### Где документировать что

| Тема | Файл |
|------|------|
| Быстрый старт для команд | [quickstart.md](quickstart.md) |
| Архитектура | [architecture.md](architecture.md) |
| Администрирование | [admin-guide.md](admin-guide.md) |
| Использование инфраструктуры | [user-guide.md](user-guide.md) |
| Описание модулей | [modules.md](modules.md) |
| История изменений | [changelog.md](changelog.md) |
| Для разработчиков | [development.md](development.md) |

---

## Инструменты разработки

### Рекомендуемые

- **Terraform** >= 1.0
- **Ansible** (ansible-core >= 2.20)
- **Git**
- **Code editor** (VS Code, IntelliJ с Terraform plugin)
- **jq** -- для работы с JSON
- **yq** -- для работы с YAML

### VS Code Extensions

- HashiCorp Terraform
- Ansible (Red Hat)
- markdownlint
- GitLens
- YAML

### Полезные команды

```bash
# Terraform (из environments/dev/)
terraform fmt -recursive          # Форматирование
terraform validate                # Валидация
terraform plan -out=tfplan        # Plan с сохранением
terraform show tfplan             # Просмотр saved plan

# Ansible (из ansible/)
ansible-playbook playbooks/site.yml           # Полная настройка
ansible-playbook playbooks/edge.yml           # Только edge
ansible-playbook playbooks/team-vms.yml       # Только team VMs
ansible-playbook playbooks/edge.yml --tags xray  # Только Xray

# Git
git log --oneline --graph         # История коммитов
git diff HEAD~1                   # Diff с предыдущим commit
```

---

## Release Process

### 1. Подготовка

```bash
# Убедиться что main branch актуален
git checkout main
git pull origin main

# Создать release branch
git checkout -b release/v3.0.0
```

### 2. Обновить документацию

- Обновить [CHANGELOG.md](changelog.md)
- Обновить версию в README.md (если есть)
- Проверить, что документация актуальна

### 3. Тестирование

```bash
cd environments/dev
terraform plan
# Проверить, что нет неожиданных изменений

# Полный цикл в test окружении
terraform apply
cd ../../ansible
ansible-playbook playbooks/site.yml
# Тестировать функционал
cd ../environments/dev
terraform destroy
```

### 4. Создать tag

```bash
git add .
git commit -m "chore: prepare release v3.0.0"
git push origin release/v3.0.0

# После merge в main
git tag -a v3.0.0 -m "Release v3.0.0"
git push origin v3.0.0
```

### 5. GitHub Release

- Создать release на GitHub
- Скопировать changelog для этой версии
- Attach artifacts (если есть)

---

## Troubleshooting Development Issues

### Terraform state locked

```bash
# Если terraform apply был прерван
terraform force-unlock <lock-id>
```

### Changes not applying

```bash
# Проверить, что используется правильное окружение
pwd
# Должно быть: .../environments/dev/

# Проверить backend
terraform init -reconfigure
```

### Module not found

```bash
# Переинициализировать
terraform init -upgrade
```

### Ansible не подключается

```bash
# Проверить inventory
ansible-inventory -i inventory/hosts.yml --list

# Проверить SSH-подключение
ssh -i <key> jump@<edge-ip>

# Запустить с verbose
ansible-playbook playbooks/edge.yml -vvv
```

---

## См. также

- [modules.md](modules.md) -- детальное описание модулей и ролей
- [changelog.md](changelog.md) -- история изменений
- [architecture.md](architecture.md) -- архитектура проекта
- [CLAUDE.md](../CLAUDE.md) -- инструкции для Claude Code
