# SSH Key Simplification & Admin Access Design

**Дата:** 2026-03-18
**Ветка:** feature/single-subnet-migration

## Контекст

Инфраструктура AI Talent Camp Hackathon. Команды — участники с разным уровнем технических знаний. Нужно максимально упростить подключение (один ключ вместо двух) и сделать обновление ключей изолированным от остальных настроек VM.

## Проблемы текущей реализации

1. Три ключа на команду (`jump-key`, `key`, `deploy-key`) — участники путаются.
2. SSH-конфиг использует разные `IdentityFile` для bastion и VM.
3. Обновление ключей (`sync-jump-keys.yml`) покрывает только edge — нет механизма обновления ключей на team VMs.
4. Нет admin-доступа ко всем VM независимо от команд.

## Цель

- Один SSH-ключ на команду для подключения (bastion + VM).
- Файл `secrets/admin-keys.txt` с pubkey-ами нескольких админов — применяется на все VM.
- Изолированный плейбук `sync-keys.yml` — обновляет только `authorized_keys`, не трогает сервисы и конфиги.
- Безопасная миграция без потери доступа к уже запущенным VM.

## Дизайн

### Ключи (Terraform)

**До:**
```
tls_private_key.team_jump_key    → secrets/team-{id}/{user}-jump-key
tls_private_key.team_vm_key      → secrets/team-{id}/{user}-key
tls_private_key.team_github_key  → secrets/team-{id}/{user}-deploy-key
```

**После:**
```
tls_private_key.team_key         → secrets/team-{id}/{user}-key
```

`team_vm_key` переименовывается в `team_key` через блок `moved {}` в `environments/dev/main.tf` — без пересоздания ресурса:

```hcl
moved {
  from = tls_private_key.team_vm_key
  to   = tls_private_key.team_key
}
```

`team_jump_key` и `team_github_key` убираются через `terraform state rm` до `apply` (см. шаг 4 миграции).

Модуль `team-credentials`: убираем переменные и `local_file` ресурсы для jump-key и github-key.

### Структура secrets

```
secrets/
  admin-keys.txt               ← НОВЫЙ: pubkey-и админов, по одному на строку
  team-{id}/
    {user}-key                 ← ОСТАЁТСЯ (единственный ключ команды)
    {user}-key.pub             ← ОСТАЁТСЯ
    ssh-config                 ← ОБНОВЛЯЕТСЯ (один IdentityFile)
    {user}-jump-key            → удаляется после миграции
    {user}-jump-key.pub        → удаляется после миграции
    {user}-deploy-key          → удаляется после миграции
    {user}-deploy-key.pub      → удаляется после миграции
  teams-credentials.json       ← ОБНОВЛЯЕТСЯ (убираем jump_key и github_key из files{})
```

### SSH-конфиг для участников (шаблон `ssh-config.tpl`)

```
Host bastion
  HostName bastion.{domain}
  User {jump_user}
  IdentityFile ~/.ssh/ai-camp/{team_user}-key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host {team_user}
  HostName {team_private_ip}
  User {team_user}
  ProxyJump bastion
  IdentityFile ~/.ssh/ai-camp/{team_user}-key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

Участник получает папку с одним ключом. Инструкция: скопировать в `~/.ssh/ai-camp/`, сделать `chmod 600`, подключиться: `ssh {user}`.

### Ansible: `sync-keys.yml`

Заменяет `sync-jump-keys.yml`. Два независимых play, только `authorized_keys` — ничего кроме.

**Play 1 — edge (jump user):**
- Читает `secrets/teams-credentials.json` (через `lookup('file', ...)`) для получения списка команд и их IP.
- Для каждой команды: добавляет `secrets/team-{id}/{user}-key.pub` с ограничениями `command="/bin/false",no-pty,no-X11-forwarding,no-agent-forwarding,permitopen="{private_ip}:22"`.
- Читает `secrets/admin-keys.txt` построчно (`lookup('file', ...)` + `splitlines()`), добавляет каждый ключ без ограничений (полный shell).
- Не содержит ролей, handlers или задач помимо `authorized_key`.

**Play 2 — team_vms (team user):**
- Читает `secrets/admin-keys.txt` построчно (аналогично play 1).
- Удостоверяется что `{user}-key.pub` присутствует в `authorized_keys` (state: present).
- Добавляет каждый admin-ключ (state: present).
- Не содержит ролей, handlers или задач помимо `authorized_key`.

**Запуск:**
```bash
# Изолированно (только ключи):
ansible-playbook playbooks/sync-keys.yml

# Автоматически вызывается из:
ansible-playbook playbooks/edge.yml
ansible-playbook playbooks/team-vms.yml
```

Импорты в `edge.yml` и `team-vms.yml`: `sync-jump-keys.yml` → `sync-keys.yml`.

### Admin-доступ

Файл `secrets/admin-keys.txt` — один pubkey на строку (формат `authorized_keys`). Пример:
```
ssh-ed25519 AAAA... admin1@example.com
ssh-ed25519 AAAA... admin2@example.com
```

Admin-ключи добавляются на:
- **Edge**: jump user, без ограничений — полный shell.
- **Все team VMs**: team user — прямой доступ через ProxyJump.

Для добавления нового админа: дописать ключ в файл → запустить `sync-keys.yml`.

## Миграция (порядок важен)

Цель: нулевой риск потери доступа к запущенным VM.

```
Шаг 1: Создать secrets/admin-keys.txt с admin pubkey-ами
Шаг 2: Написать ansible/playbooks/sync-keys.yml
Шаг 3: ansible-playbook playbooks/sync-keys.yml
        → admin-ключи добавлены на все VM (страховка доступа)
Шаг 4: # Сначала проверить точные пути ресурсов:
        terraform state list | grep -E 'jump|github'

        # Удалить для каждой команды (ресурсы вида ["team-id"]):
        # В модуле team-credentials:
        terraform state rm 'module.team_credentials.local_file.team_jump_private_key["dashboard"]'
        terraform state rm 'module.team_credentials.local_file.team_jump_public_key["dashboard"]'
        terraform state rm 'module.team_credentials.local_file.team_github_private_key["dashboard"]'
        terraform state rm 'module.team_credentials.local_file.team_github_public_key["dashboard"]'
        # В environments/dev (генерация ключей):
        terraform state rm 'tls_private_key.team_jump_key["dashboard"]'
        terraform state rm 'tls_private_key.team_github_key["dashboard"]'
        # Повторить для каждой команды из var.teams
Шаг 5: terraform apply
        → moved{} переименует team_vm_key → team_key без пересоздания VM
        → новые secrets-файлы без jump/deploy ключей
Шаг 6: ansible-playbook playbooks/sync-keys.yml
        → edge обновлён: jump authorized_keys использует {user}-key вместо {user}-jump-key
Шаг 7: Удалить старые файлы из secrets/ (jump-key, deploy-key)
```

## Что НЕ меняется

- VM-ключи команд на самих VM — `{user}-key.pub` уже там с момента создания Terraform.
- Edge jump user — admin доступ через `jump_public_key` из tfvars остаётся.
- Сетевая конфигурация, NAT, маршруты, Traefik, Xray — не трогаем.
- Security groups — не трогаем.

## Файлы к изменению

| Файл | Изменение |
|------|-----------|
| `environments/dev/main.tf` | `moved{}` для team_vm_key→team_key, удалить jump/github key ресурсы |
| `environments/dev/credentials.tf` | убрать jump/github ключи |
| `modules/team-credentials/main.tf` | убрать jump/github local_file ресурсы |
| `modules/team-credentials/variables.tf` | убрать jump/github переменные |
| `modules/team-credentials/main.tf` | обновить teams_credentials.json (убрать jump_key, github_key из files{}) |
| `templates/team/ssh-config.tpl` | заменить `-jump-key` на `-key` в строке IdentityFile bastion-хоста; VM-хост уже использует `-key` |
| `ansible/playbooks/sync-jump-keys.yml` | заменить на sync-keys.yml |
| `ansible/playbooks/edge.yml` | импорт sync-keys.yml вместо sync-jump-keys.yml |
| `ansible/playbooks/team-vms.yml` | импорт sync-keys.yml вместо sync-jump-keys.yml |
| `secrets/admin-keys.txt` | создать |
