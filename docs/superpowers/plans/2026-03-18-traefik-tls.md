# Двухуровневый Traefik + TLS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Настроить двухуровневый Traefik: edge терминирует TLS (Let's Encrypt HTTP-01), team VMs получают HTTP и сами роутят к Docker контейнерам по labels.

**Architecture:** Edge Traefik (Docker, host network) слушает 80/443, терминирует TLS, роутит `*.south.aitalenthub.ru` к нужной team VM по суффиксу team_id (`n8n-team01.* → 10.0.1.100:80`). Team Traefik (Docker, порт 80, Docker provider) роутит к контейнерам по `traefik.enable=true` labels на Docker-сети `traefik`.

**Tech Stack:** Traefik v3.3, Ansible (community.docker), Docker + Docker Compose plugin, Let's Encrypt HTTP-01 ACME.

---

## File Map

| Файл | Действие | Назначение |
|------|----------|-----------|
| `ansible/roles/traefik/templates/traefik.yml.j2` | Изменить | Статическая конфигурация edge Traefik |
| `ansible/roles/traefik/templates/dynamic.yml.j2` | Изменить | Шаблон per-team роутинга (используется в loop) |
| `ansible/roles/traefik/tasks/main.yml` | Изменить | Создание acme.json, cleanup + генерация per-team файлов, запуск контейнера |
| `ansible/roles/traefik/defaults/main.yml` | Изменить | Добавить `acme_email` |
| `ansible/group_vars/edge.yml` | Изменить | Добавить `acme_email` |
| `ansible/roles/team-traefik/defaults/main.yml` | Создать | Переменные роли (version) |
| `ansible/roles/team-traefik/tasks/main.yml` | Создать | Создать сеть traefik, конфиг, запустить контейнер |
| `ansible/roles/team-traefik/templates/traefik.yml.j2` | Создать | Статика team Traefik (HTTP only, docker provider) |
| `ansible/roles/team-traefik/handlers/main.yml` | Создать | restart traefik handler |
| `ansible/playbooks/team-vms.yml` | Изменить | Добавить роль `team-traefik` |
| `docs/user-guide.md` | Изменить | Добавить раздел «Деплой через Traefik» |

---

## Task 1: Edge Traefik static config

**Files:**
- Modify: `ansible/roles/traefik/templates/traefik.yml.j2`
- Modify: `ansible/roles/traefik/defaults/main.yml`
- Modify: `ansible/group_vars/edge.yml`

- [ ] **Step 1: Заполнить `traefik.yml.j2`**

```yaml
# ansible/roles/traefik/templates/traefik.yml.j2
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

log:
  level: INFO
```

- [ ] **Step 2: Обновить `defaults/main.yml`**

```yaml
# ansible/roles/traefik/defaults/main.yml
traefik_version: "v3.3"
acme_email: ""
```

- [ ] **Step 3: Добавить `acme_email` в `group_vars/edge.yml`**

Добавить строку (заменить на реальный email):
```yaml
acme_email: "admin@aitalenthub.ru"
```

- [ ] **Step 4: Проверить синтаксис роли**

```bash
cd ansible
ansible-playbook playbooks/edge.yml --syntax-check
```

Ожидаем: `playbook: playbooks/edge.yml` без ошибок.

- [ ] **Step 5: Commit**

```bash
git add ansible/roles/traefik/templates/traefik.yml.j2 \
        ansible/roles/traefik/defaults/main.yml \
        ansible/group_vars/edge.yml
git commit -m "feat(traefik): edge static config with ACME HTTP-01"
```

---

## Task 2: Edge Traefik dynamic config (per-team)

**Files:**
- Modify: `ansible/roles/traefik/templates/dynamic.yml.j2`
- Modify: `ansible/roles/traefik/tasks/main.yml`

- [ ] **Step 1: Заполнить шаблон `dynamic.yml.j2`**

Этот шаблон рендерится отдельно для каждой команды с переменными `team_id`, `team_ip`, `domain`.

```yaml
# ansible/roles/traefik/templates/dynamic.yml.j2
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

- [ ] **Step 2: Обновить `tasks/main.yml`**

Заменить содержимое полностью:

```yaml
# ansible/roles/traefik/tasks/main.yml
---
- name: Create Traefik config directory
  file:
    path: /etc/traefik
    state: directory
    mode: "0755"

- name: Create Traefik dynamic config directory
  file:
    path: /etc/traefik/dynamic
    state: directory
    mode: "0755"

- name: Create acme.json with correct permissions
  file:
    path: /etc/traefik/acme.json
    state: touch
    mode: "0600"
    modification_time: preserve
    access_time: preserve

- name: Deploy Traefik static config
  template:
    src: traefik.yml.j2
    dest: /etc/traefik/traefik.yml
    mode: "0644"
  notify: restart traefik

- name: Find stale dynamic config files
  find:
    paths: /etc/traefik/dynamic
    patterns: "*.yml"
  register: dynamic_files

- name: Remove stale dynamic config files
  file:
    path: "{{ item.path }}"
    state: absent
  loop: "{{ dynamic_files.files }}"
  # Удаляем отдельные файлы, не директорию — Traefik продолжает watch без ошибок

- name: Deploy per-team dynamic config
  template:
    src: dynamic.yml.j2
    dest: "/etc/traefik/dynamic/{{ hostvars[item]['team_id'] }}.yml"
    mode: "0644"
  vars:
    team_id: "{{ hostvars[item]['team_id'] }}"
    team_ip: "{{ hostvars[item]['ansible_host'] }}"
  loop: "{{ groups['team_vms'] }}"
  # team_id задаётся Terraform в ansible/templates/inventory.yml.tpl как host var
  notify: restart traefik

- name: Run Traefik container
  community.docker.docker_container:
    name: traefik
    image: "traefik:{{ traefik_version }}"
    state: started
    restart_policy: unless-stopped
    network_mode: host
    volumes:
      - /etc/traefik:/etc/traefik
```

> **Важно:** volume `/etc/traefik` монтируется rw (без `:ro`) — Traefik должен писать в `acme.json`.

- [ ] **Step 3: Проверить синтаксис**

```bash
cd ansible
ansible-playbook playbooks/edge.yml --syntax-check
```

- [ ] **Step 4: Commit**

```bash
git add ansible/roles/traefik/templates/dynamic.yml.j2 \
        ansible/roles/traefik/tasks/main.yml
git commit -m "feat(traefik): per-team dynamic routing config with cleanup"
```

---

## Task 3: Роль team-traefik

**Files:**
- Create: `ansible/roles/team-traefik/defaults/main.yml`
- Create: `ansible/roles/team-traefik/tasks/main.yml`
- Create: `ansible/roles/team-traefik/templates/traefik.yml.j2`
- Create: `ansible/roles/team-traefik/handlers/main.yml`

- [ ] **Step 1: Создать `defaults/main.yml`**

```yaml
# ansible/roles/team-traefik/defaults/main.yml
---
traefik_version: "v3.3"
```

- [ ] **Step 2: Создать шаблон `templates/traefik.yml.j2`**

```yaml
# ansible/roles/team-traefik/templates/traefik.yml.j2
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

Нет TLS, нет ACME — всё это уже на edge.

- [ ] **Step 3: Создать `tasks/main.yml`**

```yaml
# ansible/roles/team-traefik/tasks/main.yml
---
- name: Create Docker network traefik
  community.docker.docker_network:
    name: traefik
    state: present

- name: Create Traefik config directory
  file:
    path: /etc/traefik
    state: directory
    mode: "0755"

- name: Deploy Traefik static config
  template:
    src: traefik.yml.j2
    dest: /etc/traefik/traefik.yml
    mode: "0644"
  notify: restart traefik

- name: Run Traefik container
  community.docker.docker_container:
    name: traefik
    image: "traefik:{{ traefik_version }}"
    state: started
    restart_policy: unless-stopped
    ports:
      - "80:80"
    volumes:
      - /etc/traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - name: traefik
```

- [ ] **Step 4: Создать `handlers/main.yml`**

```yaml
# ansible/roles/team-traefik/handlers/main.yml
---
- name: restart traefik
  community.docker.docker_container:
    name: traefik
    state: started
    restart: true
```

- [ ] **Step 5: Проверить структуру роли**

```bash
ls ansible/roles/team-traefik/
# ожидаем: defaults  handlers  tasks  templates
```

- [ ] **Step 6: Commit**

```bash
git add ansible/roles/team-traefik/
git commit -m "feat(team-traefik): new role — HTTP-only Traefik with docker provider"
```

---

## Task 4: Подключить team-traefik в playbook

**Files:**
- Modify: `ansible/playbooks/team-vms.yml`

- [ ] **Step 1: Добавить роль `team-traefik` в `team-vms.yml`**

В секции `roles:` добавить после `docker`:

```yaml
  roles:
    - common
    - docker
    - team-traefik
```

- [ ] **Step 2: Проверить синтаксис**

```bash
cd ansible
ansible-playbook playbooks/team-vms.yml --syntax-check
```

- [ ] **Step 3: Commit**

```bash
git add ansible/playbooks/team-vms.yml
git commit -m "feat(team-vms): add team-traefik role to playbook"
```

---

## Task 5: Обновить user-guide.md

**Files:**
- Modify: `docs/user-guide.md`

- [ ] **Step 1: Добавить раздел «Деплой сервисов через Traefik»**

Вставить новый раздел (перед секцией «Nginx» или «SSL сертификаты» если такие есть, иначе в конец):

```markdown
## Деплой сервисов через Traefik

На вашей VM уже запущен Traefik — вам не нужно настраивать nginx, получать SSL сертификаты или открывать порты. Просто добавьте labels к своим Docker контейнерам.

### Конвенция доменных имён

Используйте суффикс `-<team-name>` в имени поддомена:

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
```

- [ ] **Step 2: Commit**

```bash
git add docs/user-guide.md
git commit -m "docs(user-guide): add Traefik deployment guide for teams"
```

---

## Проверка после деплоя

После `ansible-playbook playbooks/edge.yml` и `ansible-playbook playbooks/team-vms.yml`:

```bash
# 1. Edge Traefik запущен
ssh edge-vm "docker ps | grep traefik"

# 2. Dynamic configs сгенерированы
ssh edge-vm "ls /etc/traefik/dynamic/"
# ожидаем: team01.yml team02.yml ...

# 3. Team Traefik запущен
ssh -J edge team01-vm "docker ps | grep traefik"

# 4. Docker сеть traefik создана на team VM
ssh -J edge team01-vm "docker network ls | grep traefik"

# 5. HTTP→HTTPS redirect работает (с edge)
curl -v http://team01.south.aitalenthub.ru
# ожидаем: 301 → https://

# 6. HTTPS отвечает (cert выпускается ~10 сек после первого запроса)
curl -v https://team01.south.aitalenthub.ru
# ожидаем: 502 (нет контейнера) или 200 если есть — главное что TLS работает
```
