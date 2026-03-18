# Быстрый старт для команд

> **Последнее обновление:** 2026-03-18
> **Связанные документы:** [user-guide.md](user-guide.md)

## Обзор

Это руководство поможет вам быстро начать работу с инфраструктурой AI South Hub 2026. За 10 минут вы:
- Получите доступ к своей VM
- Проверите работу интернета и proxy
- Развернёте тестовое приложение

## Шаг 1: Получение credentials

Администратор предоставит вам папку с ключами доступа (например, `team-team01`).

**Содержимое папки:**
```
team-team01/
├── team01-key      # Приватный SSH-ключ (один — для bastion и VM)
├── team01-key.pub  # Публичный ключ
├── ssh-config      # Готовый SSH конфиг
├── setup.sh        # Скрипт установки для Mac/Linux
├── setup.bat       # Скрипт установки для Windows (CMD)
├── setup.ps1       # Скрипт установки для Windows (PowerShell)
└── README.md       # Инструкция
```

## Шаг 2: Настройка SSH

### Mac / Linux

```bash
cd ~/Downloads/team-team01
bash setup.sh
```

Скрипт скопирует ключ в `~/.ssh/ai-south-hack/`, добавит `Include` в `~/.ssh/config` и проверит соединение.

После этого:
```bash
ssh team01
```

### Windows (CMD — рекомендуется)

Двойной клик на `setup.bat`. После завершения подключиться:
```
ssh team01
```

### Windows (PowerShell)

Правая кнопка на `setup.ps1` → «Запустить с помощью PowerShell».

> Если ошибка политики выполнения, выполните один раз:
> ```
> Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
> ```

### Ручная установка (если скрипты не работают)

```bash
mkdir -p ~/.ssh/ai-south-hack
cp team01-key     ~/.ssh/ai-south-hack/
cp team01-key.pub ~/.ssh/ai-south-hack/
cp ssh-config     ~/.ssh/ai-south-hack/
chmod 600 ~/.ssh/ai-south-hack/team01-key

# Добавить Include в начало ~/.ssh/config
echo "Include ~/.ssh/ai-south-hack/ssh-config" | cat - ~/.ssh/config > /tmp/cfg && mv /tmp/cfg ~/.ssh/config

ssh team01
```

### Подключение через VSCode / Cursor

После выполнения `setup.sh` (или `setup.bat`/`setup.ps1`) конфиг уже добавлен в `~/.ssh/config`. Дальше:

1. Установите расширение **Remote - SSH** (VSCode/Cursor: `Cmd/Ctrl+Shift+X`)
2. `Cmd/Ctrl+Shift+P` → `Remote-SSH: Connect to Host...` → выберите `team01`
3. Откройте папку `/home/team01/` в Explorer

**Готово!** Терминал, файлы и расширения работают на team VM.

**Порты:** VSCode/Cursor автоматически пробрасывают порты — если запустите приложение на порту 3000, IDE предложит открыть его в браузере локально.

**Troubleshooting:**
- Ошибка соединения: `ssh -v team01` для диагностики
- Запрашивает пароль: `chmod 600 ~/.ssh/ai-south-hack/team01-key`

## Шаг 3: Проверка доступа

После подключения проверьте базовую функциональность:

```bash
# Проверить внешний IP (должен быть IP edge VM)
curl ifconfig.co

# Проверить доступ в интернет
curl -I https://google.com

# Проверить доступ к AI API
curl -I https://api.openai.com

# Проверить hostname
hostname

# Проверить место на диске
df -h
```

**Ожидаемые результаты:**
- Внешний IP совпадает с IP edge сервера
- Google.com доступен
- OpenAI API доступен (HTTP 200 или 401)
- Диск 65GB, свободно ~55GB

## Шаг 4: Ваш домен и HTTPS

Ваш домен: **`{team_id}.south.aitalenthub.ru`**

HTTPS сертификат выдаётся автоматически через Let's Encrypt — ничего настраивать не нужно. Достаточно задеплоить приложение через Docker (шаг 5).

Если у вас есть свой домен, создайте CNAME запись:
```
app.mydomain.com  →  CNAME  →  team01.south.aitalenthub.ru
```

Подробнее — [user-guide.md - Работа с доменами](user-guide.md#работа-с-доменами)

## Шаг 5: Развертывание тестового приложения

На team VM предустановлен Docker и Traefik. Публикация сервиса — через docker labels.

```bash
# Создать простое приложение
mkdir -p ~/workspace/test-app && cd ~/workspace/test-app

cat > docker-compose.yml << 'EOF'
services:
  app:
    image: containous/whoami
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=PathPrefix(`/`)"
    networks:
      - traefik

networks:
  traefik:
    external: true
EOF

docker compose up -d
```

Через несколько секунд сервис будет доступен по `https://{team_id}.south.aitalenthub.ru`.

### Проверка через SSH tunnel (без Traefik)

```bash
# На вашем компьютере (новый терминал)
ssh -L 8000:localhost:8000 team01

# На VM запустите приложение на порту 8000
# В браузере откройте http://localhost:8000
```

## Следующие шаги

Вы успешно подключились и развернули тестовое приложение!

**Что дальше:**

1. **Настроить production окружение**
   - Traefik уже установлен, HTTPS работает автоматически через labels
   - Добавьте нужные labels в docker-compose.yml (см. шаг 5)
   - См. [user-guide.md](user-guide.md)

2. **Настроить CI/CD**
   - Использовать `{team_id}-key` для GitHub Actions
   - Автоматический deploy при push
   - См. [user-guide.md - CI/CD](user-guide.md#cicd-и-автодеплой)

3. **Изучить advanced функции**
   - Docker и Docker Compose
   - Базы данных (PostgreSQL, MongoDB)
   - Работа с AI API
   - См. [user-guide.md](user-guide.md)

## Полезные команды

```bash
# Системная информация
htop                    # Монитор процессов
df -h                   # Место на диске
free -m                 # Использование RAM

# Сеть
ip addr                 # IP адреса
curl ifconfig.co        # Внешний IP
ss -tlnp                # Открытые порты

# Логи
sudo journalctl -f      # Все системные логи
sudo tail -f /var/log/syslog  # Syslog
```

## Получение помощи

**Проблемы с подключением?**
- [user-guide.md#troubleshooting](user-guide.md#troubleshooting)

**Нет доступа в интернет?**
- [user-guide.md#troubleshooting](user-guide.md#troubleshooting)

**Проблемы с AI API?**
- [user-guide.md#troubleshooting](user-guide.md#troubleshooting)

**Вопросы по документации:**
- См. [README.md](../README.md) для навигации по всем документам

## См. также

- [user-guide.md](user-guide.md) - подробное руководство пользователя
- [architecture.md](architecture.md) - как устроена инфраструктура
