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

1. Кликни **правой кнопкой** на файл `setup.ps1`
2. Выбери **«Запустить с помощью PowerShell»**

   > Если появится ошибка о политике выполнения:
   > открой PowerShell и выполни один раз:
   > ```
   > Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   > ```
   > Затем снова запусти `setup.ps1`

3. Подключись:
   ```
   ssh ${team_id}
   ```

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
| `setup.ps1` | Скрипт установки для Windows |

---

## Адреса

- **Bastion:** `bastion.${domain}`
- **Твой сервер:** `${team_id}.${domain}` (через bastion)
