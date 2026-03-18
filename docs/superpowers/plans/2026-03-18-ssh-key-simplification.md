# SSH Key Simplification & Admin Access — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Упростить SSH-доступ команд до одного ключа, добавить admin-доступ ко всем VM через `secrets/admin-keys.txt`, и сделать изолированный плейбук `sync-keys.yml` для обновления ключей.

**Architecture:** Terraform генерирует один ключ на команду (`team_key`, переименован из `team_vm_key` через `moved{}`). Ansible-плейбук `sync-keys.yml` управляет только `authorized_keys` на edge и team VMs независимо от остальных настроек. Модуль `team-credentials` генерирует setup-скрипты для участников из шаблонов.

**Tech Stack:** Terraform (tls_private_key, local_file, moved{}), Ansible (authorized_key module), Bash/PowerShell шаблоны

**Spec:** `docs/superpowers/specs/2026-03-18-ssh-key-simplification-design.md`

---

## Порядок выполнения (критически важен для безопасности)

Задачи 1–2 выполняются **до** Terraform-изменений — они устанавливают страховку (admin-доступ к VM).
Задачи 3–6 — код. Задача 7 — terraform state + apply. Задача 8 — cleanup.

---

## Task 1: Создать secrets/admin-keys.txt и sync-keys.yml — запустить сразу

**Это первый шаг — до любых изменений кода. Он добавляет admin-ключи на все VM как страховку.**

**Files:**
- Create: `secrets/admin-keys.txt`
- Create: `ansible/playbooks/sync-keys.yml`
- Delete: `ansible/playbooks/sync-jump-keys.yml` (в Task 8)

- [ ] **Шаг 1.1: Создать secrets/admin-keys.txt**

Файл с pubkey-ами администраторов, по одному на строку. Пример:
```
ssh-ed25519 AAAA...ваш_admin_pubkey admin@example.com
```

Заполнить реальными ключами администраторов перед продолжением.

- [ ] **Шаг 1.2: Написать ansible/playbooks/sync-keys.yml**

```yaml
---
# Синхронизирует SSH-ключи на edge и team VMs.
# Управляет ТОЛЬКО authorized_keys — не трогает сервисы, маршруты, конфиги.
# Запускать: ansible-playbook playbooks/sync-keys.yml
# Также вызывается из edge.yml и team-vms.yml.

- name: Sync team keys to edge jump user
  hosts: edge
  become: true
  tasks:
    - name: Read teams credentials
      set_fact:
        teams_data: "{{ lookup('file', playbook_dir + '/../../secrets/teams-credentials.json') | from_json }}"
      delegate_to: localhost
      become: false

    - name: Check admin-keys.txt exists
      stat:
        path: "{{ playbook_dir }}/../../secrets/admin-keys.txt"
      delegate_to: localhost
      become: false
      register: admin_keys_stat
      failed_when: not admin_keys_stat.stat.exists

    - name: Read admin public keys
      set_fact:
        admin_keys: "{{ lookup('file', playbook_dir + '/../../secrets/admin-keys.txt').splitlines() | select('match', '^ssh-') | list }}"
      delegate_to: localhost
      become: false

    - name: Add team keys with port-forward restrictions to jump user
      authorized_key:
        user: jump
        state: present
        key: "{{ lookup('file', playbook_dir + '/../../secrets/team-' + item.key + '/' + item.value.user + '-key.pub') }}"
        key_options: >-
          command="/bin/false",no-pty,no-X11-forwarding,no-agent-forwarding,permitopen="{{ item.value.private_ip }}:22"
      loop: "{{ teams_data.teams | dict2items }}"

    - name: Add admin keys to edge jump user (no restrictions)
      authorized_key:
        user: jump
        state: present
        key: "{{ item }}"
      loop: "{{ admin_keys }}"

- name: Sync admin keys to team VMs
  hosts: team_vms
  become: true
  tasks:
    - name: Check admin-keys.txt exists
      stat:
        path: "{{ playbook_dir }}/../../secrets/admin-keys.txt"
      delegate_to: localhost
      become: false
      register: admin_keys_stat
      failed_when: not admin_keys_stat.stat.exists

    - name: Read admin public keys
      set_fact:
        admin_keys: "{{ lookup('file', playbook_dir + '/../../secrets/admin-keys.txt').splitlines() | select('match', '^ssh-') | list }}"
      delegate_to: localhost
      become: false

    - name: Ensure team key is present (idempotent)
      # team_id — переменная из inventory/hosts.yml (например "dashboard"), используется для пути к ключу
      authorized_key:
        user: "{{ ansible_user }}"
        state: present
        key: "{{ lookup('file', playbook_dir + '/../../secrets/team-' + team_id + '/' + ansible_user + '-key.pub') }}"

    - name: Add admin keys to team VM
      authorized_key:
        user: "{{ ansible_user }}"
        state: present
        key: "{{ item }}"
      loop: "{{ admin_keys }}"
```

- [ ] **Шаг 1.3: Проверить что inventory существует и доступен**

```bash
cd ansible
cat inventory/hosts.yml  # убедиться что файл есть и IP адреса верны
```

- [ ] **Шаг 1.4: Запустить sync-keys.yml (dry-run)**

```bash
cd ansible
ansible-playbook playbooks/sync-keys.yml --check -v
```

Ожидаем: задачи по authorized_key показывают `changed` (dry-run, реально не меняет). Если ошибка подключения — проверить inventory и доступность edge.

- [ ] **Шаг 1.5: Запустить sync-keys.yml (реально)**

```bash
ansible-playbook playbooks/sync-keys.yml -v
```

Ожидаем: все задачи OK/changed, нет failed. После этого admin-ключи добавлены на все VM — страховка установлена.

- [ ] **Шаг 1.6: Проверить admin-доступ к edge**

```bash
ssh -i /путь/к/admin_key jump@bastion.south.aitalenthub.ru
```

Ожидаем: успешный вход с полным шеллом.

- [ ] **Шаг 1.7: Коммит**

```bash
git add ansible/playbooks/sync-keys.yml secrets/admin-keys.txt
git commit -m "feat(ansible): add sync-keys playbook and admin-keys.txt"
```

---

## Task 2: Обновить edge.yml и team-vms.yml

**Files:**
- Modify: `ansible/playbooks/edge.yml`
- Modify: `ansible/playbooks/team-vms.yml`

- [ ] **Шаг 2.1: Обновить edge.yml**

В `ansible/playbooks/edge.yml` заменить:
```yaml
- import_playbook: sync-jump-keys.yml
```
на:
```yaml
- import_playbook: sync-keys.yml
```

- [ ] **Шаг 2.2: Обновить team-vms.yml**

В `ansible/playbooks/team-vms.yml` заменить:
```yaml
- import_playbook: sync-jump-keys.yml
```
на:
```yaml
- import_playbook: sync-keys.yml
```

- [ ] **Шаг 2.3: Проверить синтаксис плейбуков**

```bash
cd ansible
ansible-playbook playbooks/edge.yml --syntax-check
ansible-playbook playbooks/team-vms.yml --syntax-check
```

Ожидаем: `playbook: playbooks/edge.yml` (без ошибок).

- [ ] **Шаг 2.4: Коммит**

```bash
git add ansible/playbooks/edge.yml ansible/playbooks/team-vms.yml
git commit -m "feat(ansible): replace sync-jump-keys with sync-keys in edge and team-vms playbooks"
```

---

## Task 3: Создать шаблоны для доставки credentials

**Files:**
- Create: `templates/team/setup.sh.tpl`
- Create: `templates/team/setup.ps1.tpl`
- Create: `templates/team/README.md.tpl`

- [ ] **Шаг 3.1: Создать templates/team/setup.sh.tpl**

```bash
#!/usr/bin/env bash
# =============================================================================
# AI South Hack — Setup SSH access for ${team_user}
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_DIR="$HOME/.ssh/ai-south-hack"
KEY_NAME="${team_user}-key"

echo "==> Создаём директорию $SSH_DIR"
mkdir -p "$SSH_DIR"

echo "==> Копируем ключи и конфиг"
cp "$SCRIPT_DIR/$KEY_NAME"     "$SSH_DIR/$KEY_NAME"
cp "$SCRIPT_DIR/$KEY_NAME.pub" "$SSH_DIR/$KEY_NAME.pub"
cp "$SCRIPT_DIR/ssh-config"    "$SSH_DIR/ssh-config"

echo "==> Устанавливаем права доступа"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/$KEY_NAME"
chmod 644 "$SSH_DIR/$KEY_NAME.pub"
chmod 644 "$SSH_DIR/ssh-config"

echo "==> Проверяем соединение..."
if ssh -F "$SSH_DIR/ssh-config" -o ConnectTimeout=10 -o BatchMode=yes ${team_user} echo "OK" 2>/dev/null; then
  echo ""
  echo "✓ Всё готово! Подключайся командой:"
  echo ""
  echo "    ssh -F ~/.ssh/ai-south-hack/ssh-config ${team_user}"
  echo ""
else
  echo ""
  echo "⚠ Ключи установлены, но соединение не проверено (VM может быть ещё недоступна)."
  echo "  Попробуй подключиться позже:"
  echo ""
  echo "    ssh -F ~/.ssh/ai-south-hack/ssh-config ${team_user}"
  echo ""
fi
```

- [ ] **Шаг 3.2: Создать templates/team/setup.ps1.tpl**

```powershell
# =============================================================================
# AI South Hack — Setup SSH access for ${team_user}
# =============================================================================
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SshDir = Join-Path $HOME ".ssh\ai-south-hack"
$KeyName = "${team_user}-key"

Write-Host "==> Создаём директорию $SshDir"
New-Item -ItemType Directory -Force -Path $SshDir | Out-Null

Write-Host "==> Копируем ключи и конфиг"
Copy-Item "$ScriptDir\$KeyName"     "$SshDir\$KeyName"     -Force
Copy-Item "$ScriptDir\$KeyName.pub" "$SshDir\$KeyName.pub" -Force
Copy-Item "$ScriptDir\ssh-config"   "$SshDir\ssh-config"   -Force

Write-Host "==> Устанавливаем права доступа на приватный ключ"
$acl = Get-Acl "$SshDir\$KeyName"
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
  $env:USERNAME, "FullControl", "Allow"
)
$acl.SetAccessRule($rule)
Set-Acl "$SshDir\$KeyName" $acl

Write-Host "==> Проверяем соединение..."
$result = ssh -F "$SshDir\ssh-config" -o ConnectTimeout=10 -o BatchMode=yes ${team_user} echo OK 2>&1
if ($LASTEXITCODE -eq 0) {
  Write-Host ""
  Write-Host "v  Всё готово! Подключайся командой:" -ForegroundColor Green
  Write-Host ""
  Write-Host "   ssh -F $HOME\.ssh\ai-south-hack\ssh-config ${team_user}" -ForegroundColor Cyan
  Write-Host ""
} else {
  Write-Host ""
  Write-Host "!  Ключи установлены, но соединение не проверено (VM может быть ещё недоступна)." -ForegroundColor Yellow
  Write-Host "   Попробуй подключиться позже:" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "   ssh -F $HOME\.ssh\ai-south-hack\ssh-config ${team_user}" -ForegroundColor Cyan
  Write-Host ""
}
```

- [ ] **Шаг 3.3: Создать templates/team/README.md.tpl**

```markdown
# AI South Hack — Подключение к серверу команды ${team_user}

## Быстрый старт

### Mac / Linux

1. Открой терминал
2. Перейди в папку с этим файлом:
   ```
   cd ~/Downloads/team-${team_user}
   ```
3. Запусти скрипт:
   ```
   bash setup.sh
   ```
4. Подключись:
   ```
   ssh -F ~/.ssh/ai-south-hack/ssh-config ${team_user}
   ```

### Windows

1. Кликни **правой кнопкой** на файл `setup.ps1`
2. Выбери **«Запустить с помощью PowerShell»**

   > Если появится ошибка о политике выполнения:
   > открой PowerShell и выполни один раз:
   > ```
   > Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   > ```
   > Затем снова запусти `setup.ps1`

3. Подключись через терминал (PowerShell или CMD):
   ```
   ssh -F $HOME\.ssh\ai-south-hack\ssh-config ${team_user}
   ```

---

## Ручная установка (если скрипт не работает)

### Mac / Linux

```bash
mkdir -p ~/.ssh/ai-south-hack
cp ${team_user}-key     ~/.ssh/ai-south-hack/
cp ${team_user}-key.pub ~/.ssh/ai-south-hack/
cp ssh-config           ~/.ssh/ai-south-hack/
chmod 600 ~/.ssh/ai-south-hack/${team_user}-key
ssh -F ~/.ssh/ai-south-hack/ssh-config ${team_user}
```

### Windows (PowerShell)

```powershell
New-Item -ItemType Directory -Force "$HOME\.ssh\ai-south-hack"
Copy-Item "${team_user}-key"     "$HOME\.ssh\ai-south-hack\"
Copy-Item "${team_user}-key.pub" "$HOME\.ssh\ai-south-hack\"
Copy-Item "ssh-config"           "$HOME\.ssh\ai-south-hack\"
ssh -F "$HOME\.ssh\ai-south-hack\ssh-config" ${team_user}
```

---

## Что внутри этого архива

| Файл | Описание |
|------|----------|
| `${team_user}-key` | Приватный SSH-ключ (не передавай никому) |
| `${team_user}-key.pub` | Публичный SSH-ключ |
| `ssh-config` | Конфиг SSH для автоматического ProxyJump через bastion |
| `setup.sh` | Скрипт установки для Mac/Linux |
| `setup.ps1` | Скрипт установки для Windows |

---

## Адреса

- **Bastion:** `bastion.${domain}`
- **Твой сервер:** `${team_user}.${domain}` (через bastion)
```

- [ ] **Шаг 3.4: Коммит**

```bash
git add templates/team/setup.sh.tpl templates/team/setup.ps1.tpl templates/team/README.md.tpl
git commit -m "feat(templates): add setup scripts and README for participant credential delivery"
```

---

## Task 4: Обновить ssh-config.tpl

**Files:**
- Modify: `templates/team/ssh-config.tpl`

- [ ] **Шаг 4.1: Обновить templates/team/ssh-config.tpl**

Ключевое изменение: **оба хоста** (`bastion` и `${team_user}`) теперь используют **один и тот же** `IdentityFile` — `${team_user}-key`. Раньше bastion использовал отдельный `-jump-key`. Это и есть суть упрощения.

Текущее содержимое (строка 16): `IdentityFile ~/.ssh/ai-camp/${team_user}-jump-key`

Новое содержимое файла:
```
# =============================================================================
# AI South Hack SSH Config for ${team_user}
# =============================================================================
# Usage:
#   1. Copy this folder to ~/.ssh/ai-south-hack/
#   2. chmod 600 ~/.ssh/ai-south-hack/*-key
#   3. ssh -F ~/.ssh/ai-south-hack/ssh-config ${team_user}
# =============================================================================

Host bastion
  HostName bastion.${domain}
  User ${jump_user}
  IdentityFile ~/.ssh/ai-south-hack/${team_user}-key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host ${team_user}
  HostName ${team_private_ip}
  User ${team_user}
  ProxyJump bastion
  IdentityFile ~/.ssh/ai-south-hack/${team_user}-key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

- [ ] **Шаг 4.2: Коммит**

```bash
git add templates/team/ssh-config.tpl
git commit -m "feat(templates): update ssh-config to use single key and ai-south-hack dir"
```

---

## Task 5: Обновить модуль team-credentials

**Files:**
- Modify: `modules/team-credentials/variables.tf`
- Modify: `modules/team-credentials/main.tf`

- [ ] **Шаг 5.1: Обновить variables.tf — убрать jump/github переменные**

Удалить все переменные для jump и github ключей (строки 35–66 в текущем файле). Оставить только:
```hcl
variable "team_private_keys" {
  description = "Map of team private keys (OpenSSH format)"
  type        = map(string)
  sensitive   = true
}

variable "team_public_keys" {
  description = "Map of team public keys (OpenSSH format)"
  type        = map(string)
}
```

- [ ] **Шаг 5.2: Обновить main.tf — убрать jump/github ресурсы, добавить setup-файлы**

Удалить секции `Jump Keys` и `GitHub Deploy Keys` целиком (ресурсы `team_jump_private_key`, `team_jump_public_key`, `team_github_private_key`, `team_github_public_key`).

В секции `VM Keys` переименовать ресурсы:
- `team_vm_private_key` → `team_private_key`
- `team_vm_public_key` → `team_public_key`

И обновить переменные в них: `var.team_vm_private_keys` → `var.team_private_keys`, `var.team_vm_public_keys` → `var.team_public_keys`.

Добавить после блока `SSH Config Files`:

```hcl
# =============================================================================
# Participant Setup Scripts
# =============================================================================

resource "local_file" "team_setup_sh" {
  for_each = var.teams

  filename        = "${path.module}/${var.secrets_path}/team-${each.key}/setup.sh"
  content = templatefile("${path.module}/../../templates/team/setup.sh.tpl", {
    team_user = each.value.user
  })
  file_permission = "0755"
}

resource "local_file" "team_setup_ps1" {
  for_each = var.teams

  filename = "${path.module}/${var.secrets_path}/team-${each.key}/setup.ps1"
  content = templatefile("${path.module}/../../templates/team/setup.ps1.tpl", {
    team_user = each.value.user
  })
}

resource "local_file" "team_readme" {
  for_each = var.teams

  filename = "${path.module}/${var.secrets_path}/team-${each.key}/README.md"
  content = templatefile("${path.module}/../../templates/team/README.md.tpl", {
    team_user = each.value.user
    domain    = var.domain
  })
}
```

Обновить `teams_credentials_json` — убрать `jump_key` и `github_key` из `files {}`, обновить ссылки:
```hcl
files = {
  key        = "${team_config.user}-key"
  ssh_config = "ssh-config"
  setup_sh   = "setup.sh"
  setup_ps1  = "setup.ps1"
  readme     = "README.md"
}
```

Обновить `ssh_command`:
```hcl
ssh_command = "ssh -F ~/.ssh/ai-south-hack/ssh-config ${team_config.user}"
```

- [ ] **Шаг 5.3: Validate модуль изолированно**

```bash
cd environments/dev
terraform validate
```

Ожидаем ошибки о несуществующих переменных (ещё не обновили credentials.tf) — это нормально, фиксируем в следующей задаче.

- [ ] **Шаг 5.4: Коммит**

```bash
git add modules/team-credentials/variables.tf modules/team-credentials/main.tf
git commit -m "feat(team-credentials): simplify to single key, add setup scripts generation"
```

---

## Task 6: Обновить environments/dev — main.tf и credentials.tf

**Files:**
- Modify: `environments/dev/main.tf`
- Modify: `environments/dev/credentials.tf`

- [ ] **Шаг 6.1: Обновить main.tf — убрать jump/github ключи, добавить moved{}**

Заменить секцию SSH Keys Generation (строки 90–110):

```hcl
# =============================================================================
# SSH Keys Generation for Teams
# =============================================================================

# Single key per team — used for both bastion access and VM login
resource "tls_private_key" "team_key" {
  for_each  = var.teams
  algorithm = "ED25519"
}

moved {
  from = tls_private_key.team_vm_key
  to   = tls_private_key.team_key
}
```

- [ ] **Шаг 6.2: Обновить credentials.tf — убрать jump/github, передать team_key**

Заменить:
```hcl
  team_jump_private_keys   = { for k, v in tls_private_key.team_jump_key : k => v.private_key_openssh }
  team_jump_public_keys    = { for k, v in tls_private_key.team_jump_key : k => v.public_key_openssh }
  team_vm_private_keys     = { for k, v in tls_private_key.team_vm_key : k => v.private_key_openssh }
  team_vm_public_keys      = { for k, v in tls_private_key.team_vm_key : k => v.public_key_openssh }
  team_github_private_keys = { for k, v in tls_private_key.team_github_key : k => v.private_key_openssh }
  team_github_public_keys  = { for k, v in tls_private_key.team_github_key : k => v.public_key_openssh }
```

на:
```hcl
  team_private_keys = { for k, v in tls_private_key.team_key : k => v.private_key_openssh }
  team_public_keys  = { for k, v in tls_private_key.team_key : k => v.public_key_openssh }
```

- [ ] **Шаг 6.3: Validate**

```bash
cd environments/dev
terraform validate
```

Ожидаем: `Success! The configuration is valid.`

- [ ] **Шаг 6.4: Коммит**

```bash
git add environments/dev/main.tf environments/dev/credentials.tf
git commit -m "feat(dev): simplify to single team_key, add moved{} block for safe rename"
```

---

## Task 7: Terraform state cleanup + apply

**ВНИМАНИЕ: Перед этим шагом убедиться что admin-ключи добавлены (Task 1 выполнен).**

- [ ] **Шаг 7.1: Проверить текущий стейт**

```bash
cd environments/dev
terraform state list | grep -E 'jump|github'
```

Ожидаем строки вида:
```
module.team_credentials.local_file.team_jump_private_key["dashboard"]
module.team_credentials.local_file.team_jump_public_key["dashboard"]
module.team_credentials.local_file.team_github_private_key["dashboard"]
module.team_credentials.local_file.team_github_public_key["dashboard"]
tls_private_key.team_jump_key["dashboard"]
tls_private_key.team_github_key["dashboard"]
```

Также проверить что vm_key ещё в стейте (будет переименован):
```bash
terraform state list | grep team_vm_key
```

- [ ] **Шаг 7.2: Удалить из стейта jump/github ресурсы**

Используем loop чтобы не пропустить ни одну команду:

```bash
# Автоматически находим все team_id из стейта и удаляем нужные ресурсы:
for team_id in $(terraform state list | grep 'tls_private_key.team_jump_key' | sed 's/.*\["\(.*\)"\].*/\1/'); do
  echo "==> Removing resources for team: $team_id"
  terraform state rm "module.team_credentials.local_file.team_jump_private_key[\"$team_id\"]"
  terraform state rm "module.team_credentials.local_file.team_jump_public_key[\"$team_id\"]"
  terraform state rm "module.team_credentials.local_file.team_github_private_key[\"$team_id\"]"
  terraform state rm "module.team_credentials.local_file.team_github_public_key[\"$team_id\"]"
  terraform state rm "tls_private_key.team_jump_key[\"$team_id\"]"
  terraform state rm "tls_private_key.team_github_key[\"$team_id\"]"
done

# Проверить что jump/github ресурсов больше нет:
terraform state list | grep -E 'jump|github'
# Ожидаем: пустой вывод
```

- [ ] **Шаг 7.3: Проверить план — убедиться что нет destroy для VM**

```bash
terraform plan
```

Ожидаем:
- `tls_private_key.team_key` — moved (no changes)
- Новые `local_file` ресурсы для setup.sh, setup.ps1, README.md — `will be created`
- Обновлённые `local_file` для ssh-config и teams-credentials.json — `will be updated`
- **Никакого** `cloudru_evolution_compute` в изменениях

Если в плане есть `destroy` для compute или network ресурсов — СТОП, разобраться прежде чем apply.

- [ ] **Шаг 7.4: Apply**

```bash
terraform apply
```

Ожидаем: apply без ошибок, новые файлы в secrets/.

- [ ] **Шаг 7.5: Проверить сгенерированные файлы**

```bash
ls secrets/team-*/
# Должны появиться: setup.sh, setup.ps1, README.md
# {user}-key и {user}-key.pub — остались
# {user}-jump-key и {user}-deploy-key — ещё есть (удалим в Task 8)

cat secrets/team-dashboard/ssh-config
# Должны быть пути ~/.ssh/ai-south-hack/

bash -n secrets/team-dashboard/setup.sh
# Синтаксис bash без ошибок
```

- [ ] **Шаг 7.6: Запустить sync-keys.yml ещё раз — обновить edge**

```bash
cd ansible
ansible-playbook playbooks/sync-keys.yml -v
```

Теперь edge jump authorized_keys использует `{user}-key.pub` вместо `{user}-jump-key.pub`. Проверить что команды ещё могут подключаться.

---

## Task 8: Cleanup

- [ ] **Шаг 8.1: Удалить sync-jump-keys.yml**

```bash
git rm ansible/playbooks/sync-jump-keys.yml
```

- [ ] **Шаг 8.2: Удалить старые ключи из secrets/**

```bash
# Для каждой команды:
rm secrets/team-*/*-jump-key secrets/team-*/*-jump-key.pub
rm secrets/team-*/*-deploy-key secrets/team-*/*-deploy-key.pub
```

- [ ] **Шаг 8.3: Финальная проверка подключения команд**

Проверить что хотя бы одна команда может подключиться через новый ssh-config:

```bash
ssh -F secrets/team-dashboard/ssh-config dashboard echo "connection OK"
```

Ожидаем: `connection OK`

- [ ] **Шаг 8.4: Финальный коммит**

```bash
git add -A
git commit -m "feat(credentials): complete SSH key simplification — single key, setup scripts, admin access"
```

---

## Быстрая проверка результата

После завершения всех задач:

```bash
# 1. Структура secrets/team-*/
ls secrets/team-dashboard/
# Должно быть: .gitkeep dashboard-key dashboard-key.pub setup.sh setup.ps1 README.md ssh-config

# 2. Terraform стейт чист
cd environments/dev && terraform plan
# Expected: No changes. Your infrastructure matches the configuration.

# 3. Ansible идемпотентен
cd ansible && ansible-playbook playbooks/sync-keys.yml --check
# Expected: 0 changed, 0 failed

# 4. Подключение команды работает
ssh -F secrets/team-dashboard/ssh-config dashboard echo OK
```
