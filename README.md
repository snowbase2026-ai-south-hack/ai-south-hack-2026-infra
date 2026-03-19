# AI South Hub 2026 — Инфраструктура для команд

> Всё, что нужно участникам хакатона: подключение, деплой, AI API, совместная работа.

## Что у вас есть

Каждая команда получает выделенную виртуальную машину в облаке Cloud.ru Evolution:

| Параметр | Значение |
|----------|----------|
| **ОС** | Ubuntu 22.04 LTS |
| **CPU** | 4 vCPU |
| **RAM** | 8 GB |
| **Диск** | 65 GB SSD |
| **Доступ** | Полный sudo |
| **Домен** | `{team_id}.south.aitalenthub.ru` (HTTPS, Let's Encrypt) |

### Предустановленное ПО

На VM уже установлено и настроено — ничего ставить не нужно:

| Категория | Что установлено |
|-----------|----------------|
| **Контейнеры** | Docker Engine, Docker Compose |
| **Python** | Python 3.12, [uv](https://docs.astral.sh/uv/) (быстрый package manager) |
| **Node.js** | Node.js 22 LTS (через [nvm](https://github.com/nvm-sh/nvm) в `/opt/nvm`), npm |
| **Go** | Go 1.24 |
| **AI-ассистент** | [Claude Code](https://claude.ai/code) (`claude` в терминале) |
| **Тестирование** | [Playwright](https://playwright.dev/) + Chromium |
| **Reverse proxy** | Traefik (docker provider) — деплой через docker labels |
| **Утилиты** | `btop`, `htop`, `bat`, `rg` (ripgrep), `fd`, `jq`, `ncdu`, `tmux`, `tree`, `nmap`, `tcpdump` |

### Алиасы bash

```
ll → ls -alF    la → ls -A    .. → cd ..    ... → cd ../..
cat → batcat    fd → fdfind   df → df -h    free → free -h
```

---

## Архитектура

```
Вы / IDE  ──SSH──►  bastion.south.aitalenthub.ru  ──►  Ваша VM (10.0.1.x)
          ──HTTPS─► {team_id}.south.aitalenthub.ru ──►  team-traefik ──► ваш контейнер
```

- **Edge VM** — единственная точка входа с публичным IP
- **Traefik на edge** — HTTPS-терминация (Let's Encrypt), маршрутизация `{team_id}.south.aitalenthub.ru` → team VM
- **team-traefik на вашей VM** — HTTP-only, docker provider; вы деплоите через docker labels
- **Xray** — прозрачное проксирование AI API через TPROXY

---

## Подключение

Вы получаете папку `team-{id}/` с SSH ключом и скриптами настройки.

### Настройка (один раз)

**Mac / Linux:**
```bash
cd ~/Downloads/team-{id}
bash setup.sh
```

**Windows (CMD):** двойной клик на `setup.bat`

**Windows (PowerShell):** правая кнопка на `setup.ps1` → «Запустить с помощью PowerShell»

> Если ошибка политики выполнения: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

Скрипт копирует ключ в `~/.ssh/ai-south-hack/`, добавляет `Include` в `~/.ssh/config` и проверяет соединение.

### Подключение по SSH

```bash
ssh {team_id}
```

### Persistent session через tmux (рекомендуется)

Используйте tmux, чтобы сессия не терялась при разрыве соединения:

```bash
ssh -t {team_id} "tmux new-session -As dev"
```

Эта команда создаёт (или подключается к существующей) сессию `dev`. Если соединение оборвётся — просто выполните команду снова, и вы вернётесь ровно туда, где были.

Claude Code отлично работает внутри tmux — просто запустите `claude` в tmux-сессии.

### Подключение через VSCode / Cursor

После выполнения `setup.sh` (или `setup.bat` / `setup.ps1`) SSH конфиг уже добавлен:

1. Установите расширение **Remote - SSH** (`Cmd/Ctrl+Shift+X`)
2. `Cmd/Ctrl+Shift+P` → `Remote-SSH: Connect to Host...` → выберите `{team_id}`
3. Откройте папку `/home/{team_id}/` в Explorer

VSCode/Cursor автоматически пробрасывают порты — если запустите приложение на порту 3000, IDE предложит открыть его в браузере.

### Ручная установка (если скрипты не работают)

```bash
mkdir -p ~/.ssh/ai-south-hack
cp {team_id}-key     ~/.ssh/ai-south-hack/
cp {team_id}-key.pub ~/.ssh/ai-south-hack/
cp ssh-config        ~/.ssh/ai-south-hack/
chmod 600 ~/.ssh/ai-south-hack/{team_id}-key

# Добавить Include в начало ~/.ssh/config
echo "Include ~/.ssh/ai-south-hack/ssh-config" | cat - ~/.ssh/config > /tmp/cfg && mv /tmp/cfg ~/.ssh/config

ssh {team_id}
```

### Копирование файлов

```bash
# Загрузить на VM
scp file.txt {team_id}:~/workspace/

# Скачать с VM
scp {team_id}:~/workspace/file.txt ./
```

---

## Деплой приложения

На вашей VM уже запущен Traefik с docker provider. Публикация сервиса — через docker labels. Не нужно настраивать nginx, получать SSL или открывать порты.

### Быстрый пример

Создайте `docker-compose.yml`:

```yaml
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
```

Запустите:

```bash
docker compose up -d
```

Через ~10 секунд приложение доступно на `https://{team_id}.south.aitalenthub.ru`.

### Полный пример: FastAPI + PostgreSQL

```yaml
services:
  web:
    build: .
    restart: always
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.web.rule=Host(`{team_id}.south.aitalenthub.ru`)"
      - "traefik.http.services.web.loadbalancer.server.port=8000"
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/mydb
    depends_on:
      - db
    command: uvicorn main:app --host 0.0.0.0 --port 8000

  db:
    image: postgres:18-alpine
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

### Правила Traefik

- Контейнер **обязательно** в сети `traefik` (`networks: - traefik`)
- Без `traefik.enable=true` Traefik игнорирует контейнер
- Укажите `server.port` если контейнер слушает не на порту 80
- Маппинг `ports:` не нужен — Traefik обращается через Docker-сеть

### Дополнительные поддомены

Кроме основного `{team_id}.south.aitalenthub.ru`, можно использовать поддомены с суффиксом:

| URL | Пример использования |
|-----|---------------------|
| `{team_id}.south.aitalenthub.ru` | Главная страница |
| `api-{team_id}.south.aitalenthub.ru` | API |
| `n8n-{team_id}.south.aitalenthub.ru` | n8n |

Укажите нужный Host в `traefik.http.routers.*.rule`.

---

## Доступ к AI API

AI API (OpenAI, Anthropic и др.) доступны с вашей VM напрямую — через прозрачный прокси Xray на edge VM. Никаких специальных настроек не нужно.

Просто используйте API ключи как обычно:

```bash
# Пример: проверка доступа к OpenAI
curl -I https://api.openai.com

# В коде — стандартные переменные окружения
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."

# Библиотеки работают без изменений
python -c "from anthropic import Anthropic; print(Anthropic().messages.create(...))"
```

Весь трафик к AI API проксируется через Xray (TPROXY) автоматически — вам не нужно указывать прокси.

---

## Совместная работа

Несколько человек могут работать на одной VM одновременно — подключайтесь по SSH с одним и тем же ключом `{team_id}-key`.

### Shared tmux сессия (парная работа)

Один участник создаёт сессию:
```bash
ssh -t {team_id} "tmux new-session -As dev"
```

Другие подключаются к ней:
```bash
ssh -t {team_id} "tmux attach -t dev"
```

Все видят один терминал в реальном времени — удобно для парного программирования и совместной отладки.

### Независимая работа

Каждый может создать свою tmux-сессию:
```bash
ssh -t {team_id} "tmux new-session -As myname"
```

---

## Проверка после подключения

```bash
# Внешний IP (должен совпадать с edge VM)
curl ifconfig.co

# Доступ в интернет
curl -I https://google.com

# Доступ к AI API
curl -I https://api.openai.com

# Место на диске (ожидается ~55GB свободно)
df -h

# Docker работает
docker run --rm hello-world
```

---

## Troubleshooting

### SSH: не подключается

```bash
# Диагностика
ssh -v {team_id}

# Проверить права на ключ
chmod 600 ~/.ssh/ai-south-hack/{team_id}-key

# Проверить доступность bastion
ping bastion.south.aitalenthub.ru
```

### Приложение не доступно по HTTPS

```bash
# Контейнер запущен?
docker ps

# Контейнер в сети traefik?
docker inspect <container> | jq '.[0].NetworkSettings.Networks'

# Labels на месте?
docker inspect <container> | jq '.[0].Config.Labels'
```

### Нет места на диске

```bash
ncdu ~                              # Найти большие директории
docker system prune -a --volumes    # Очистить Docker
sudo journalctl --vacuum-time=7d    # Очистить логи
```

### Docker: Permission denied

```bash
sudo usermod -aG docker $USER
# Перезайти по SSH
```

---

## Полезные команды

```bash
# Мониторинг
btop                        # CPU и память
docker stats                # Ресурсы контейнеров

# Docker
docker compose logs -f      # Логи всех сервисов
docker exec -it <c> bash    # Войти в контейнер

# Поиск
rg "pattern" ./             # Поиск по содержимому (ripgrep)
fd "*.py" ./                # Поиск файлов
```

---

## Для администраторов

- [docs/admin-guide.md](docs/admin-guide.md) — развёртывание и управление
- [docs/architecture.md](docs/architecture.md) — детальная архитектура
- [docs/modules.md](docs/modules.md) — Terraform модули

Быстрый деплой: `cd environments/dev && terraform init && terraform apply`, затем `cd ansible && ansible-playbook playbooks/edge.yml && ansible-playbook playbooks/team-vms.yml`.
