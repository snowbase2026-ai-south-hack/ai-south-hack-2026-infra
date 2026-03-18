# Руководство для команд AI South Hub 2026

> **Последнее обновление:** 2026-03-18
> **Для команд участников**
> **Связанные документы:** [quickstart.md](quickstart.md)

## Введение

Это полное руководство для команд участников AI South Hub 2026. Вы получаете выделенную виртуальную машину (VM) в облаке с полным контролем и root доступом.

**Что у вас есть:**
- Виртуальная машина Ubuntu 22.04 LTS
- 4 vCPU, 8GB RAM, 65GB SSD
- Полный sudo доступ
- Доступ в интернет (включая AI API)
- Доменное имя `<team-id>.south.aitalenthub.ru`
- SSH доступ через центральную точку входа
- Docker, Node.js, Python (uv), Claude Code — уже установлены

**Что вам нужно сделать:**
- Развернуть ваше приложение через Docker
- Добавить Traefik labels в docker-compose.yml — HTTPS настроится автоматически
- Настроить автоматический деплой (опционально)

---

## Содержание

1. [Подключение к VM](#подключение-к-vm)
2. [Предустановленное ПО](#предустановленное-по)
3. [Деплой сервисов через Traefik](#деплой-сервисов-через-traefik)
4. [Работа с доменами](#работа-с-доменами)
5. [Развертывание приложений](#развертывание-приложений)
6. [CI/CD и автодеплой](#cicd-и-автодеплой)
7. [Базы данных](#базы-данных)
8. [Мониторинг и логи](#мониторинг-и-логи)
9. [Troubleshooting](#troubleshooting)

---

## Подключение к VM

### Через терминал (SSH)

Вы получите папку с SSH ключами (например, `team-team01`).

**Шаг 1: Копирование ключей**

```bash
# Скопировать папку с ключами
cp -r team-team01 ~/.ssh/ai-south-hack

# Установить правильные права доступа
chmod 700 ~/.ssh/ai-south-hack
chmod 600 ~/.ssh/ai-south-hack/*-key
chmod 644 ~/.ssh/ai-south-hack/*.pub
chmod 644 ~/.ssh/ai-south-hack/ssh-config
```

**Шаг 2: Подключение**

```bash
# Использовать готовый конфиг
ssh -F ~/.ssh/ai-south-hack/ssh-config team01

# Или добавить в ваш ~/.ssh/config
cat ~/.ssh/ai-south-hack/ssh-config >> ~/.ssh/config
ssh team01
```

**Структура ключей:**

| Файл | Назначение |
|------|------------|
| `{team_id}-key` | Единственный SSH ключ — для bastion и VM |
| `{team_id}-key.pub` | Публичный ключ |
| `ssh-config` | Готовый SSH конфиг (bastion + VM) |
| `setup.sh` / `setup.bat` / `setup.ps1` | Установочные скрипты |

### Через IDE (VSCode/Cursor)

Работа через IDE удобнее - вы редактируете файлы как локальные.

**VSCode:**

1. Установите расширение **"Remote - SSH"**
2. Нажмите `Cmd/Ctrl+Shift+P` → `Remote-SSH: Connect to Host...`
3. Выберите `Configure SSH Hosts...` → `~/.ssh/config`
4. Добавьте содержимое из `~/.ssh/ai-south-hack/ssh-config`
5. Подключитесь к `team01`

**Cursor:**

Cursor построен на VSCode и использует те же расширения - следуйте инструкции для VSCode.

Подробная инструкция: [quickstart.md - Подключение через IDE](quickstart.md#вариант-c-подключение-через-vscodecursor)

### Копирование файлов

```bash
# Через scp
scp -F ~/.ssh/ai-south-hack/ssh-config file.txt team01:~/workspace/

# Загрузить файл с VM
scp -F ~/.ssh/ai-south-hack/ssh-config team01:~/workspace/file.txt ./
```

---

## Предустановленное ПО

Ansible настраивает VM автоматически — вам не нужно ничего устанавливать вручную.

### Docker

Docker Engine установлен и запущен. Ваш пользователь уже добавлен в группу `docker`.

```bash
docker --version
docker compose version

# Запустить контейнер
docker run hello-world
```

### Node.js и npm

Node.js LTS установлен через [nvm](https://github.com/nvm-sh/nvm) в `/opt/nvm`.

```bash
node --version
npm --version
nvm --version

# Установить другую версию Node.js
nvm install 20
nvm use 20
nvm alias default 20
```

### Python и uv

[uv](https://docs.astral.sh/uv/) — быстрый Python package manager, установлен в `/usr/local/bin/uv`. Заменяет pip, venv, virtualenv.

```bash
uv --version

# Создать проект
uv init myproject
cd myproject

# Добавить зависимость
uv add fastapi uvicorn

# Запустить скрипт
uv run python main.py

# Создать виртуальное окружение
uv venv
source .venv/bin/activate
```

### Claude Code

[Claude Code](https://claude.ai/code) — AI-ассистент для разработки, установлен в `~/.local/bin/claude`.

```bash
claude --version

# Запустить в текущей директории
claude

# Запустить с конкретной задачей
claude "помоги настроить docker-compose для fastapi + postgres"
```

### Playwright

[Playwright](https://playwright.dev/) установлен глобально через npm. Chromium и системные зависимости уже скачаны.

```bash
# Использование через npx
npx playwright --version

# В Python-проекте
uv add playwright
uv run playwright install  # устанавливать браузеры не нужно — уже есть

# Пример теста
uv run pytest tests/ --browser chromium
```

### Утилиты командной строки

| Команда | Описание |
|---------|----------|
| `btop` / `htop` | Мониторинг ресурсов CPU/памяти |
| `bat` (alias `cat`) | Просмотр файлов с подсветкой синтаксиса |
| `rg` (ripgrep) | Быстрый поиск по файлам |
| `fd` | Быстрый поиск файлов (замена `find`) |
| `jq` | Работа с JSON в терминале |
| `ncdu` | Интерактивный просмотр использования диска |
| `tmux` | Мультиплексор терминала |
| `tree` | Дерево директорий |
| `nmap` | Сканирование сети |
| `tcpdump` | Анализ сетевого трафика |

### Алиасы bash

В `.bashrc` настроены удобные алиасы:

```bash
ll          # ls -alF
la          # ls -A
..          # cd ..
...         # cd ../..
df          # df -h
du          # du -h
free        # free -h
cat         # batcat --style=plain (с подсветкой)
fd          # fdfind
```

---

## Деплой сервисов через Traefik

На вашей VM уже запущен Traefik — вам не нужно настраивать nginx, получать SSL сертификаты или открывать порты. Просто добавьте labels к своим Docker контейнерам.

### Конвенция доменных имён

Используйте суффикс `-<team-id>` в имени поддомена:

| URL | Что это |
|-----|---------|
| `team01.south.aitalenthub.ru` | Главная страница вашей команды |
| `n8n-team01.south.aitalenthub.ru` | n8n вашей команды |
| `api-team01.south.aitalenthub.ru` | API вашей команды |
| `anything-team01.south.aitalenthub.ru` | Любой сервис |

Замените `team01` на ваш team ID.

### Пример docker-compose.yml

```yaml
services:
  n8n:
    image: n8nio/n8n
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`n8n-team01.south.aitalenthub.ru`)"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"

networks:
  traefik:
    external: true   # сеть создана Ansible, не пересоздавать
```

После `docker compose up -d` сервис будет доступен по HTTPS через ~10 секунд (время выпуска сертификата).

### Правила

- Контейнер **обязательно** должен быть в сети `traefik` (`networks: - traefik`)
- Без `traefik.enable=true` Traefik игнорирует контейнер
- Укажите `server.port` если контейнер слушает не на 80
- Не нужен маппинг `ports:` — Traefik обращается к контейнеру напрямую через Docker сеть

---

## Работа с доменами

### Ваш стандартный домен

Вы получаете: **`<team-id>.south.aitalenthub.ru`**

Где `<team-id>` -- идентификатор вашей команды (например, `team01`, `dashboard`)

### Имя команды в домене

Имя команды в домене определяется идентификатором в `terraform.tfvars` (ключ в maps `teams`). Например, если ваша команда зарегистрирована как `team01`, ваш домен будет `team01.south.aitalenthub.ru`. Если как `dashboard` -- `dashboard.south.aitalenthub.ru`.

Для изменения имени обратитесь к администратору.

### Использование собственного домена

Если у вас есть свой домен, вы можете использовать его для доступа к вашему приложению.

**Шаг 1: Создать запрос на добавление домена**

Для корректной маршрутизации кастомного домена через центральный reverse proxy (Traefik), создайте [issue в репозитории](https://github.com/AI-Talent-Camp-2026/ai-talent-camp-2026-infra/issues/new):

```
Заголовок: Добавление кастомного домена для teamXX
Описание:
  Команда: team01
  Кастомный домен: app.mydomain.com
  Тип: HTTP + HTTPS (TLS passthrough)
```

Администратор добавит ваш домен в конфигурацию Traefik (обычно 1 рабочий день).

**Шаг 2: Настройка DNS**

После одобрения запроса, зайдите в панель управления вашего DNS провайдера (Cloudflare, Namecheap, и т.д.):

**CNAME**
```
Тип: CNAME
Имя: app (или любое другое: www, api, и т.д.)
Значение: team01.south.aitalenthub.ru
TTL: Auto или 300
```

**Пример:**
```
app.mydomain.com → team01.south.aitalenthub.ru (CNAME)
```

**Шаг 3: Проверка DNS (может занять до 48 часов)**

```bash
# Проверить CNAME запись
dig app.mydomain.com

# Должно быть (для CNAME):
# app.mydomain.com. 300 IN CNAME team01.south.aitalenthub.ru.
# team01.south.aitalenthub.ru. 300 IN A <IP edge VM>
```

**Важно:**
- ⚠️ Без добавления домена в конфигурацию Traefik (Шаг 1), ваш кастомный домен не будет работать
- ✅ Стандартный домен `<team-id>.south.aitalenthub.ru` работает сразу без дополнительных настроек

---

## Развертывание приложений

### Docker Compose

Docker Compose позволяет описать всё приложение в одном файле.

#### Пример: Python FastAPI

**docker-compose.yml:**

```yaml
services:
  web:
    build: .
    container_name: fastapi-app
    restart: always
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.web.rule=Host(`team01.south.aitalenthub.ru`)"
      - "traefik.http.services.web.loadbalancer.server.port=8000"
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/mydb
    depends_on:
      - db
    command: uvicorn main:app --host 0.0.0.0 --port 8000

  db:
    image: postgres:15-alpine
    container_name: postgres
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: mydb
    volumes:
      - postgres-data:/var/lib/postgresql/data

volumes:
  postgres-data:

networks:
  traefik:
    external: true
```

**Dockerfile:**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

Или с uv (быстрее):

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY . .

CMD ["uv", "run", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## CI/CD и автодеплой

### GitHub Actions

Подключение к VM из CI/CD идёт **через jump-сервер (bastion)** — так же, как при ручном SSH. Используется **один SSH ключ** для обоих переходов.

#### Шаг 1: Добавить ключ в GitHub Secrets

```bash
# Скопировать приватный ключ
cat ~/.ssh/ai-south-hack/team01-key
```

В GitHub: Settings → Secrets and variables → Actions → New repository secret
- Name: `DEPLOY_KEY`
- Value: содержимое файла `team01-key`

**Примечание:** Приватный IP вашей VM и hostname bastion возьмите из выданного вам `ssh-config`.

#### Шаг 2: Создать workflow с ProxyJump

В workflow подключаемся к VM через jump-сервер (bastion). Используется один ключ для обоих переходов.

Значения `BASTION_HOST`, `TEAM_VM_IP`, `TEAM_USER` берите из выданного файла `ssh-config`.

`.github/workflows/deploy.yml`:

```yaml
name: Deploy to Production

on:
  push:
    branches: [ main ]

env:
  BASTION_HOST: bastion.south.aitalenthub.ru
  TEAM_VM_IP: 10.0.1.11
  TEAM_USER: team01

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup SSH and known hosts
      run: |
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        ssh-keyscan -H ${{ env.BASTION_HOST }} >> ~/.ssh/known_hosts

    - name: Deploy with Docker Compose
      env:
        DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}
      run: |
        echo "$DEPLOY_KEY" > ~/.ssh/deploy_key
        chmod 600 ~/.ssh/deploy_key
        ssh -o ProxyCommand="ssh -i ~/.ssh/deploy_key -W %h:%p jump@${{ env.BASTION_HOST }}" \
            -i ~/.ssh/deploy_key ${{ env.TEAM_USER }}@${{ env.TEAM_VM_IP }} << 'REMOTE'
          cd ~/workspace/myapp
          git pull origin main
          docker compose down
          docker compose build
          docker compose up -d
        REMOTE
```

---

## Базы данных

### PostgreSQL в Docker

**docker-compose.yml:**

```yaml
services:
  postgres:
    image: postgres:18-alpine
    container_name: postgres
    restart: always
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
      POSTGRES_DB: mydb
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql

volumes:
  postgres-data:
```

**Подключение:**

```bash
# Из приложения на той же VM
DATABASE_URL=postgresql://myuser:mypassword@localhost:5432/mydb

# Подключиться через psql
docker exec -it postgres psql -U myuser -d mydb
```

### MongoDB в Docker

```yaml
services:
  mongodb:
    image: mongo:7
    container_name: mongodb
    restart: always
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: password
    ports:
      - "27017:27017"
    volumes:
      - mongodb-data:/data/db

volumes:
  mongodb-data:
```

**Подключение:**

```bash
# Connection string
mongodb://admin:password@localhost:27017

# Подключиться через mongosh
docker exec -it mongodb mongosh -u admin -p password
```

### Redis в Docker

```yaml
services:
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: always
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data

volumes:
  redis-data:
```

**Подключение:**

```bash
# Из приложения
REDIS_URL=redis://localhost:6379

# Подключиться через redis-cli
docker exec -it redis redis-cli
```

---

## Мониторинг и логи

### Системные логи

```bash
# Все системные логи
sudo journalctl -f

# Логи конкретного сервиса
sudo journalctl -u myapp -f

# Логи за последний час
sudo journalctl --since "1 hour ago"
```

### Docker логи

```bash
# Логи контейнера
docker logs -f myapp

# Логи всех контейнеров в docker-compose
docker compose logs -f

# Логи конкретного сервиса
docker compose logs -f app
```

### Мониторинг ресурсов

```bash
# CPU и память (интерактивно)
btop
# или
htop

# Использование диска
df -h

# Интерактивный просмотр использования диска
ncdu ~

# Docker использование диска
docker system df

# Очистка Docker (осторожно!)
docker system prune -a
```

---

## Troubleshooting

### Не могу подключиться по SSH

**Проверить права на ключи:**

```bash
ls -la ~/.ssh/ai-south-hack/
# Должно быть:
# drwx------ (700) для директории
# -rw------- (600) для приватных ключей
# -rw-r--r-- (644) для публичных ключей

# Исправить если нужно
chmod 700 ~/.ssh/ai-south-hack
chmod 600 ~/.ssh/ai-south-hack/*-key
chmod 644 ~/.ssh/ai-south-hack/*.pub
```

**Проверить подключение:**

```bash
# С verbose выводом
ssh -vvv -F ~/.ssh/ai-south-hack/ssh-config team01
```

**Проверить доступность центральной точки входа:**

```bash
ping bastion.south.aitalenthub.ru
```

### Приложение не доступно извне

**1. Проверить что контейнер запущен и в сети traefik:**

```bash
docker ps
docker inspect <container_name> | jq '.[0].NetworkSettings.Networks'
```

**2. Проверить Traefik labels:**

```bash
# Посмотреть текущие labels
docker inspect <container_name> | jq '.[0].Config.Labels'

# Убедиться что traefik.enable=true есть
# и контейнер в сети traefik
```

**3. Проверить открытые порты:**

```bash
sudo ss -tlnp | grep -E ':(80|443|3000|5000|8000)'
```

**4. Проверить DNS:**

```bash
# Проверить что домен указывает на правильный IP
dig team01.south.aitalenthub.ru
```

### Ошибка "Permission denied" в Docker

```bash
# Добавить пользователя в группу docker
sudo usermod -aG docker $USER

# Применить изменения (нужно перезайти)
newgrp docker

# Или выйти и зайти снова
exit
ssh -F ~/.ssh/ai-south-hack/ssh-config team01
```

### Нет места на диске

```bash
# Посмотреть использование
df -h

# Найти большие директории интерактивно
ncdu ~

# Очистить Docker
docker system prune -a --volumes

# Очистить логи
sudo journalctl --vacuum-time=7d
```

### Docker контейнер постоянно перезапускается

```bash
# Посмотреть логи
docker logs myapp

# Посмотреть последние 100 строк
docker logs --tail 100 myapp

# Запустить контейнер в интерактивном режиме для отладки
docker run -it myapp /bin/sh
```

### Высокая нагрузка CPU/памяти

```bash
# Посмотреть процессы
btop

# Посмотреть использование ресурсов Docker контейнерами
docker stats

# Ограничить ресурсы контейнера в docker-compose.yml:
services:
  app:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
```

---

## Полезные команды

### Системные

```bash
# Информация о системе
uname -a
lsb_release -a

# Использование ресурсов
btop
free -h
df -h
ncdu ~

# Поиск по файлам (ripgrep)
rg "ключевое слово" ./

# Поиск файлов (fd)
fd "*.py" ./
```

### Docker

```bash
# Список контейнеров
docker ps -a

# Логи
docker logs -f container_name

# Войти в контейнер
docker exec -it container_name /bin/bash

# Статистика ресурсов
docker stats

# Очистка
docker system prune -a
```

### Git

```bash
# Клонировать репозиторий
git clone https://github.com/user/repo.git

# Обновить
git pull origin main

# Посмотреть статус
git status

# История коммитов
git log --oneline
```

---

## См. также

- [quickstart.md](quickstart.md) - быстрый старт для новичков
- [README.md](../README.md) - общая информация о проекте

---

**Нужна помощь?** Создайте [issue в репозитории](https://github.com/AI-Talent-Camp-2026/ai-talent-camp-2026-infra/issues/new).
