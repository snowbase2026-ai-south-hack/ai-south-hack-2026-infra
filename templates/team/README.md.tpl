# AI South Hack — Подключение к серверу команды ${team_id}

## Быстрый старт

### Mac / Linux

1. Открой терминал
2. Перейди в папку с этим файлом:
   ```
   cd ~/Downloads/team-${team_id}
   ```
3. Запусти скрипт:
   ```
   bash setup.sh
   ```
4. Подключись:
   ```
   ssh ${team_id}
   ```

### Windows

**Вариант A — через CMD (рекомендуем):**

1. Дважды кликни на файл **`setup.bat`**
2. Подключись:
   ```
   ssh ${team_id}
   ```

**Вариант B — через PowerShell:**

1. Кликни правой кнопкой на `setup.ps1` → **«Запустить с помощью PowerShell»**

   > Если ошибка о политике выполнения — открой PowerShell и выполни один раз:
   > ```
   > Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   > ```

---

## Что делает скрипт

1. Копирует ключ в `~/.ssh/ai-south-hack/`
2. Добавляет `Include` в `~/.ssh/config` — после этого работает просто `ssh ${team_id}`
3. Проверяет соединение

---

## Ручная установка (если скрипт не работает)

### Mac / Linux

```bash
mkdir -p ~/.ssh/ai-south-hack
cp ${team_id}-key     ~/.ssh/ai-south-hack/
cp ${team_id}-key.pub ~/.ssh/ai-south-hack/
cp ssh-config         ~/.ssh/ai-south-hack/
chmod 600 ~/.ssh/ai-south-hack/${team_id}-key

# Добавь строку в начало ~/.ssh/config:
echo "Include ~/.ssh/ai-south-hack/ssh-config" | cat - ~/.ssh/config > /tmp/sshcfg && mv /tmp/sshcfg ~/.ssh/config

ssh ${team_id}
```

### Windows (PowerShell)

```powershell
New-Item -ItemType Directory -Force "$HOME\.ssh\ai-south-hack"
Copy-Item "${team_id}-key"     "$HOME\.ssh\ai-south-hack\"
Copy-Item "${team_id}-key.pub" "$HOME\.ssh\ai-south-hack\"
Copy-Item "ssh-config"         "$HOME\.ssh\ai-south-hack\"

# Добавь строку в начало $HOME\.ssh\config:
$cfg = "$HOME\.ssh\config"
$old = if (Test-Path $cfg) { Get-Content $cfg -Raw } else { "" }
Set-Content $cfg "Include $HOME\.ssh\ai-south-hack\ssh-config`r`n`r`n$old" -NoNewline

ssh ${team_id}
```

---

## Что внутри этого архива

| Файл | Описание |
|------|----------|
| `${team_id}-key` | Приватный SSH-ключ (не передавай никому) |
| `${team_id}-key.pub` | Публичный SSH-ключ |
| `ssh-config` | SSH-конфиг с настройками bastion и твоего сервера |
| `setup.sh` | Скрипт установки для Mac/Linux |
| `setup.bat` | Скрипт установки для Windows через CMD (дважды кликнуть) |
| `setup.ps1` | Скрипт установки для Windows через PowerShell |

---

## Persistent сессия (tmux)

tmux сохраняет терминальную сессию при разрыве соединения — процессы продолжают работать.

**Создать или подключиться к сессии:**
```bash
ssh ${team_id}
tmux new-session -As dev
```

Если соединение оборвалось — снова подключись и выполни:
```bash
ssh ${team_id}
tmux attach -t dev
```

---

## Адреса

- **Bastion:** `bastion.${domain}`
- **Твой сервер:** `${team_id}.${domain}` (через bastion)

---

## Подробнее

Деплой через docker-compose, доступное ПО, AI API, совместная работа —
см. **README.md в корне репозитория** (выдаётся организаторами или доступен на GitHub).
