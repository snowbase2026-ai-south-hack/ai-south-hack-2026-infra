# Быстрый старт для команд

> **Последнее обновление:** 2026-03-17
> **Связанные документы:** [user-guide.md](user-guide.md), [troubleshooting.md](troubleshooting.md)

## Обзор

Это руководство поможет вам быстро начать работу с инфраструктурой AI Talent Camp. За 10 минут вы:
- Получите доступ к своей VM
- Проверите работу интернета и proxy
- Развернёте тестовое приложение

## Шаг 1: Получение credentials

Администратор предоставит вам папку с ключами доступа (например, `team-team01`).

**Содержимое папки:**
```
team-team01/
├── team01-jump-key      # Ключ для подключения к bastion
├── team01-key           # Ключ для подключения к вашей VM
├── team01-deploy-key    # Ключ для GitHub Actions (опционально)
├── *.pub                # Публичные ключи
└── ssh-config           # Готовый SSH конфиг
```

## Шаг 2: Настройка SSH

### Вариант A: Использование готового конфига

```bash
# 1. Скопировать папку с ключами
cp -r team-team01 ~/.ssh/ai-camp

# 2. Установить правильные права доступа
chmod 700 ~/.ssh/ai-camp
chmod 600 ~/.ssh/ai-camp/*-key
chmod 644 ~/.ssh/ai-camp/*.pub
chmod 644 ~/.ssh/ai-camp/ssh-config

# 3. Подключиться
ssh -F ~/.ssh/ai-camp/ssh-config team01
```

### Вариант B: Добавить в ~/.ssh/config

Если хотите интегрировать с вашим SSH конфигом:

```bash
# Скопировать ключи
cp team-team01/*-key* ~/.ssh/

# Добавить в ~/.ssh/config
cat >> ~/.ssh/config << 'EOF'

Host ai-camp-bastion
    HostName bastion.south.aitalenthub.ru
    User jump
    IdentityFile ~/.ssh/team01-jump-key
    IdentitiesOnly yes

Host team01
    HostName 10.0.2.11
    User team01
    ProxyJump ai-camp-bastion
    IdentityFile ~/.ssh/team01-key
    IdentitiesOnly yes
EOF

# Подключиться
ssh team01
```

### Вариант C: Подключение через VSCode/Cursor

Работа через IDE даёт вам возможность редактировать файлы на удаленной машине как локальные, использовать терминал, отладку и все расширения.

#### VSCode

**1. Установить расширение Remote - SSH**

- Откройте VSCode
- Нажмите `Cmd/Ctrl+Shift+X` (Extensions)
- Найдите и установите **"Remote - SSH"** от Microsoft
- Перезапустите VSCode (если требуется)

**2. Настроить SSH конфиг**

```bash
# Скопировать папку с ключами
cp -r team-team01 ~/.ssh/ai-camp

# Установить правильные права доступа
chmod 700 ~/.ssh/ai-camp
chmod 600 ~/.ssh/ai-camp/*-key
chmod 644 ~/.ssh/ai-camp/*.pub
chmod 644 ~/.ssh/ai-camp/ssh-config
```

**3. Добавить конфиг в VSCode**

Вариант A - использовать готовый конфиг напрямую:
- Нажмите `Cmd/Ctrl+Shift+P`
- Введите `Remote-SSH: Connect to Host...`
- Нажмите `Configure SSH Hosts...`
- Выберите `~/.ssh/config`
- Добавьте в конец файла содержимое из `~/.ssh/ai-camp/ssh-config`:

```bash
# Скопировать конфиг
cat ~/.ssh/ai-camp/ssh-config >> ~/.ssh/config
```

Или скопируйте вручную содержимое файла `ssh-config`.

**4. Подключиться**

- Нажмите `Cmd/Ctrl+Shift+P`
- Введите `Remote-SSH: Connect to Host...`
- Выберите `team01` (или ваш номер команды)
- Подождите пока VSCode подключится
- Откройте папку `/home/team01/workspace`

**Готово!** Теперь вы работаете на удаленной машине. Все файлы, терминал и расширения работают на team VM.

#### Cursor

Cursor построен на базе VSCode и использует те же расширения:

1. Откройте Cursor
2. Установите расширение **"Remote - SSH"** (как в VSCode)
3. Следуйте той же инструкции, что и для VSCode
4. Подключитесь к `team01`

#### Полезные советы для работы через IDE

- **Терминал:** `Terminal -> New Terminal` открывает терминал прямо на team VM
- **Файлы:** Все файлы в Explorer -- это файлы на удаленной машине
- **Расширения:** Некоторые расширения нужно установить отдельно для Remote
- **Порты:** VSCode автоматически пробрасывает порты (например, если запустите приложение на порту 3000, VSCode предложит открыть его в браузере)

#### Troubleshooting

**Ошибка "Could not establish connection":**
- Проверьте права на ключи: `ls -la ~/.ssh/ai-camp/`
- Убедитесь что можете подключиться через обычный SSH: `ssh -F ~/.ssh/ai-camp/ssh-config team01`

**Запрашивает пароль:**
- Права на ключи неправильные, выполните: `chmod 600 ~/.ssh/ai-camp/*-key`

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

## Шаг 4: Ваш домен

Каждая команда получает доменное имя для публикации своего приложения.

### Стандартный домен

Ваш домен: **`<team-name>.south.aitalenthub.ru`**

Где `<team-name>` -- идентификатор вашей команды (например, `team01`, `dashboard`).

### Использование собственного домена

Если у вас есть свой домен, направьте его на выданный поддомен:

**1. Создайте CNAME запись у своего DNS провайдера:**

```
Тип:     CNAME
Имя:     app (или любое другое)
Значение: team01.south.aitalenthub.ru
TTL:     Auto или 300
```

**2. Проверьте настройку (может занять до 48 часов):**

```bash
dig app.mydomain.com
# Должна быть CNAME запись на team01.south.aitalenthub.ru
```

**3. Настройте SSL на вашей VM:**

```bash
# Установите certbot (если еще не установлен)
sudo apt install -y certbot python3-certbot-nginx

# Получите сертификат для вашего домена
sudo certbot --nginx -d app.mydomain.com
```

Подробнее см. [user-guide.md - Работа с доменами](user-guide.md#работа-с-доменами)

## Шаг 5: Развертывание тестового приложения

Давайте развернём простое веб-приложение для проверки routing.

### Python + Flask

```bash
# Установить Python и pip
sudo apt update
sudo apt install -y python3 python3-pip python3-venv

# Создать приложение
mkdir -p ~/workspace/test-app
cd ~/workspace/test-app

# Создать виртуальное окружение
python3 -m venv venv
source venv/bin/activate

# Установить Flask
pip install flask

# Создать простое приложение
cat > app.py << 'EOF'
from flask import Flask, jsonify
import socket

app = Flask(__name__)

@app.route('/')
def home():
    return jsonify({
        'status': 'ok',
        'hostname': socket.gethostname(),
        'message': 'AI Talent Camp Infrastructure'
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOF

# Запустить приложение
python app.py
```

Приложение запустится на `http://10.0.2.11:8000`

### Проверка с вашего компьютера

Для доступа к приложению извне нужно настроить Nginx и SSL сертификат (см. [user-guide.md](user-guide.md#настройка-окружения)).

Временно можно проверить через SSH tunnel:

```bash
# На вашем компьютере (в новом терминале)
ssh -F ~/.ssh/ai-camp/ssh-config -L 8000:localhost:8000 team01

# Откройте в браузере
http://localhost:8000
```

Должны увидеть JSON ответ со статусом "ok".

## Шаг 6: Остановка приложения

```bash
# В терминале где запущен Flask, нажмите Ctrl+C

# Деактивировать venv
deactivate
```

## Следующие шаги

Вы успешно подключились и развернули тестовое приложение!

**Что дальше:**

1. **Настроить production окружение**
   - Установить веб-сервер (Nginx)
   - Получить SSL сертификат
   - Настроить systemd service для автозапуска
   - См. [user-guide.md](user-guide.md)

2. **Настроить CI/CD**
   - Использовать `<user>-deploy-key` для GitHub Actions
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
- [troubleshooting.md#ssh-connection-refused](troubleshooting.md#ssh-connection-refused)

**Нет доступа в интернет?**
- [troubleshooting.md#vm-не-имеет-доступа-в-интернет](troubleshooting.md#vm-не-имеет-доступа-в-интернет)

**Проблемы с AI API?**
- [troubleshooting.md#tproxy-не-работает](troubleshooting.md#tproxy-не-работает)

**Вопросы по документации:**
- См. [README.md](../README.md) для навигации по всем документам

## См. также

- [user-guide.md](user-guide.md) - подробное руководство пользователя
- [architecture.md](architecture.md) - как устроена инфраструктура
- [troubleshooting.md](troubleshooting.md) - решение проблем
