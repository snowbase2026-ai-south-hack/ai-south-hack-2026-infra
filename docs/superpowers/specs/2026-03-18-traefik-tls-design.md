# Двухуровневый Traefik + TLS

**Дата:** 2026-03-18
**Статус:** Утверждён

## Контекст

Нужно дать командам хакатона простой способ деплоить сервисы (n8n, API, фронтенд и т.д.) по HTTPS без ручного управления сертификатами. Домен `south.aitalenthub.ru` уже настроен: `*.south.aitalenthub.ru → edge floating IP`.

## Архитектура

### Схема потока запроса

```
Браузер → HTTPS → Edge Traefik (10.0.1.10)
                    ├ TLS termination (Let's Encrypt HTTP-01)
                    ├ n8n-team01.south.aitalenthub.ru → 10.0.1.100:80
                    └ api-team02.south.aitalenthub.ru → 10.0.1.101:80
                              ↓ HTTP (внутри 10.0.1.0/24)
                    Team Traefik :80 (Docker provider)
                              ↓
                    Docker контейнеры команды
```

### Конвенция поддоменов

DNS-записей добавлять не нужно — `*.south.aitalenthub.ru → edge IP` покрывает все плоские поддомены.

| Поддомен | Назначение |
|----------|-----------|
| `team01.south.aitalenthub.ru` | Главное приложение team01 |
| `n8n-team01.south.aitalenthub.ru` | n8n команды team01 |
| `api-team01.south.aitalenthub.ru` | API команды team01 |
| `anything-team01.south.aitalenthub.ru` | Любой сервис team01 |

**Правило:** суффикс `-<team_id>` в имени поддомена. Edge роутит по этому суффиксу.

## Компоненты

### Edge Traefik

**Роль в Ansible:** `traefik` (существующая, заполнить шаблоны)
**Запуск:** Docker, `network_mode: host`

**Статическая конфигурация (`traefik.yml`):**
```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: "{{ acme_email }}"
      storage: /etc/traefik/acme.json
      httpChallenge:
        entryPoint: web

providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true

api:
  dashboard: true
  insecure: false
```

**Динамическая конфигурация (шаблон Ansible, один файл на команду):**

`/etc/traefik/dynamic/{{ team_id }}.yml` — генерируется из `inventory`:
```yaml
http:
  routers:
    {{ team_id }}:
      rule: "Host(`{{ team_id }}.{{ domain }}`) || HostRegexp(`.*-{{ team_id }}\\.{{ domain }}`)"
      service: {{ team_id }}
      tls:
        certResolver: letsencrypt
  services:
    {{ team_id }}:
      loadBalancer:
        servers:
          - url: "http://{{ team_ip }}:80"
```

**Volume-маппинги:**
- `/etc/traefik:/etc/traefik` (rw — нужно для записи `acme.json`)
- `/var/run/docker.sock` — НЕ монтируется (edge не управляет team контейнерами)

### Team Traefik

**Роль в Ansible:** `team-traefik` (новая роль)
**Запуск:** Docker, порт 80

**Статическая конфигурация:**
```yaml
entryPoints:
  web:
    address: ":80"

providers:
  docker:
    exposedByDefault: false
    network: traefik

log:
  level: INFO
```

**Docker Compose для запуска:**
```yaml
services:
  traefik:
    image: "traefik:{{ traefik_version }}"
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - /etc/traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - traefik

networks:
  traefik:
    name: traefik
```

**Никакого TLS на team Traefik** — сертификаты живут только на edge.

### Security Group

Изменений не требуется. Текущий SG уже открывает `TCP 80` от `10.0.1.0/24` (edge → team VM).

## Деплой нового сервиса командой

Команде достаточно добавить labels в `docker-compose.yml`:

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
    external: true
```

Edge Traefik автоматически выпускает TLS-сертификат при первом запросе (~10 секунд). Команда ничего не знает про TLS.

## Добавление новой команды (admin)

```bash
# 1. Добавить в terraform.tfvars
teams = {
  "team03" = { user = "team03", ip = "10.0.1.103", public_keys = [], ... }
}

# 2. Применить
cd environments/dev && terraform apply
cd ../../ansible
ansible-playbook playbooks/edge.yml      # генерирует /etc/traefik/dynamic/team03.yml
ansible-playbook playbooks/team-vms.yml  # ставит Docker + Team Traefik на team03 VM
```

Edge Traefik подхватывает новый dynamic файл автоматически (watch mode), cert выпускается при первом обращении.

## Смена поддомена команды

```bash
# terraform.tfvars: переименовать ключ, например "team01" → "dashboard"
# terraform apply + ansible-playbook edge.yml
# Старый dynamic файл удаляется, создаётся новый
# Edge выпускает cert для новых доменов (HTTP-01), старые истекут сами
```

## Ansible

### Изменения в существующей роли `traefik`

- `templates/traefik.yml.j2` — заполнить (статика, см. выше)
- `templates/dynamic.yml.j2` — переименовать в шаблон per-team, итерировать по `teams`
- `defaults/main.yml` — добавить `acme_email`
- `tasks/main.yml` — добавить создание `acme.json` с правами `600`, убрать монтирование docker.sock

### Новая роль `team-traefik`

- `tasks/main.yml` — создать директории, задеплоить конфиг, запустить через Docker Compose
- `templates/traefik.yml.j2` — статика без TLS
- `templates/docker-compose.yml.j2` — compose файл с traefik network
- `defaults/main.yml` — `traefik_version`

### Playbooks

| Playbook | Что делает |
|----------|-----------|
| `edge.yml` | Деплоит edge Traefik + генерирует все per-team dynamic файлы |
| `team-vms.yml` | Ставит Docker, Team Traefik, создаёт сеть `traefik` |

## Документация для команд

Обновить `docs/user-guide.md`: раздел «Деплой сервисов через Traefik» с примером docker-compose labels и конвенцией именования поддоменов.
