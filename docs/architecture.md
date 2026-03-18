# Архитектура AI South Hub 2026 Infrastructure

> **Последнее обновление:** 2026-03-17
> **Связанные документы:** [modules.md](modules.md), [admin-guide.md](admin-guide.md)

## Обзор

AI South Hub 2026 Infrastructure -- это проект для развертывания безопасной и управляемой инфраструктуры в Cloud.ru Evolution для проведения AI-хакатона.

**Ключевые принципы:**
- Единая точка входа (Edge/NAT сервер)
- Изоляция команд через security groups (доступ только с edge IP)
- Прозрачное проксирование AI API
- Terraform для провизионинга, Ansible для конфигурации
- HTTPS termination на edge VM с автоматическими Let's Encrypt сертификатами

**Двухуровневая модель:**
- **Terraform** -- провизионинг VM, сетей, security groups, SSH-ключей
- **Ansible** -- вся постнастройка: Docker, Traefik, Xray, NAT, iptables

---

## Содержание

- [Высокоуровневая схема](#высокоуровневая-схема)
- [Компоненты инфраструктуры](#компоненты-инфраструктуры)
- [Сетевая топология](#сетевая-топология)
- [Потоки данных](#потоки-данных)
- [Security](#security)
- [Масштабирование](#масштабирование)

---

## Высокоуровневая схема

```
                    Internet
                        |
              +-------- +--------+
              |   DNS Records    |
              |*.south.aitalenthub.ru|
              +---------+--------+
                        |
        +-----------------------------------------------+
        |     Cloud.ru Evolution                        |
        |  +----------------------------------------+  |
        |  |  Subnet 10.0.1.0/24  (routed_network)  |  |
        |  |                                        |  |
        |  |  +------------------+                  |  |
        |  |  |  Edge/NAT VM     |  10.0.1.10       |  |
        |  |  |  Floating IP     |  (interface_     |  |
        |  |  |  +------------+  |  security_       |  |
        |  |  |  |  Traefik   |  |  enabled=false)  |  |
        |  |  |  |   (Docker) |  |                  |  |
        |  |  |  +------------+  |                  |  |
        |  |  |  |    Xray    |  |                  |  |  <- systemd
        |  |  |  |  (systemd) |  |                  |  |
        |  |  |  +------------+  |                  |  |
        |  |  |  |    NAT     |  |                  |  |  <- iptables
        |  |  |  |  (iptables)|  |                  |  |
        |  |  |  +------------+  |                  |  |
        |  |  +------------------+                  |  |
        |  |          | NAT + TPROXY                |  |
        |  |  +--------+--------+                   |  |
        |  |  | Team01 | Team02 | ...               |  |
        |  |  |   VM   |   VM   |                   |  |
        |  |  |10.0.1.x|10.0.1.x|                   |  |
        |  |  | 4vCPU  | 4vCPU  |                   |  |
        |  |  |  8GB   |  8GB   |                   |  |
        |  |  +--------+--------+                   |  |
        |  +----------------------------------------+  |
        +-----------------------------------------------+
```

## Компоненты инфраструктуры

### 1. Edge/NAT VM

**Роль:** Единственная точка входа и выхода из инфраструктуры.

**Характеристики:**
- Floating IP (публичный адрес)
- Один сетевой интерфейс в подсети 10.0.1.0/24 (`interface_security_enabled=false`, firewall через iptables)
- 2 vCPU, 4GB RAM, 20GB SSD
- Ubuntu 22.04 LTS

**Запущенные сервисы** (настраиваются через Ansible):

#### Traefik (Docker контейнер)
- **Назначение:** Reverse proxy с HTTPS termination и ACME HTTP-01
- **Режим:** HTTPS termination на edge VM — SSL-сертификат выдаётся Let's Encrypt на edge VM, трафик расшифровывается здесь
- **Routing:** По hostname (`team01.south.aitalenthub.ru` -> Team01 VM:80)
- **Порты:** 80 (HTTP, редирект на HTTPS), 443 (HTTPS termination) → проксируется на Team VM по HTTP:80
- **Конфигурация:** `/etc/traefik/traefik.yml`, `/etc/traefik/dynamic/`
- **Кастомные домены:** Поддерживаются через явное добавление в dynamic конфигурацию

#### Xray (systemd сервис)
- **Назначение:** Прозрачное проксирование AI API и соцсетей
- **Механизм:** TPROXY (transparent proxy)
- **Протоколы:** Shadowsocks, VLESS, VMess, Trojan (конфигурируется)
- **Конфигурация:** `/etc/xray/config.json`
- **Бинарный файл:** `/usr/local/share/xray/xray`
- **Почему systemd:** TPROXY требует `IP_TRANSPARENT` socket option

#### NAT (iptables)
- **Назначение:** Маршрутизация обычного трафика в интернет
- **Механизм:** MASQUERADE + hairpin NAT
- **Цель:** Весь трафик, не перехваченный TPROXY

#### TPROXY (iptables mangle)
- **Назначение:** Прозрачный перехват трафика
- **Механизм:** iptables mangle + policy routing
- **Цель:** AI API, YouTube, соцсети (по geosite правилам)

### 2. Team VM

**Роль:** Рабочая среда для каждой команды.

**Характеристики:**
- Private IP (без публичного доступа), статический адрес через `cidrhost()` или явный IP в конфигурации teams
- 4 vCPU, 8GB RAM, 65GB SSD
- Ubuntu 22.04 LTS
- Рабочая директория: `/home/<user>/workspace`

**Предустановлено через Ansible:**
- Базовые пакеты (curl, wget, btop, htop, bat, ripgrep, fd-find, jq, tmux, tree, ncdu, vim, git и др.)
- Docker + Docker Compose
- Node.js LTS (через nvm в `/opt/nvm`)
- Python package manager uv (`/usr/local/bin/uv`)
- Claude Code (`~/.local/bin/claude`)
- Playwright + Chromium (с системными зависимостями)
- Настроенный `.bashrc` с алиасами (bat, fd, ll, цветной prompt и др.)

---

## Сетевая топология

### Подсети

В Cloud.ru Evolution нет ресурса VPC -- подсети создаются как самостоятельные ресурсы. Нет ресурса route table -- статические маршруты настраиваются на team VMs.

```
Subnet (10.0.1.0/24) -- routed_network = true
|-- Edge VM:       10.0.1.10 + Floating IP (interface_security_enabled=false)
|-- Team01 VM:     10.0.1.11
|-- Team02 VM:     10.0.1.12
|-- Dashboard VM:  10.0.1.100
|-- ...
```

### Routing

#### Edge VM
```
Destination         Gateway         Interface
0.0.0.0/0          internet        eth0
10.0.1.0/24        local           eth0
```

#### Team VMs
```
Destination         Gateway              Interface
0.0.0.0/0          10.0.1.10 (edge)     eth0
10.0.1.0/24        local                eth0
```

**Важно:** Маршрут по умолчанию для team VMs направлен на IP edge VM (10.0.1.10). Настраивается через netplan (Ansible).

### Security Groups

#### Edge SG

**Ingress:**
| Протокол | Порт | Источник | Описание |
|----------|------|----------|----------|
| TCP | 22 | 0.0.0.0/0 | SSH |
| TCP | 80 | 0.0.0.0/0 | HTTP |
| TCP | 443 | 0.0.0.0/0 | HTTPS |
| ANY | - | 10.0.1.0/24 | From subnet |
| ICMP | - | 0.0.0.0/0 | Ping |

**Egress:**
| Протокол | Порт | Назначение | Описание |
|----------|------|------------|----------|
| ANY | - | 0.0.0.0/0 | All outbound |

#### Team SG

**Ingress:**
| Протокол | Порт | Источник | Описание |
|----------|------|----------|----------|
| TCP | 22 | 10.0.1.10/32 | SSH (только с edge IP) |
| TCP | 80 | 10.0.1.10/32 | HTTP от Traefik (только с edge IP) |
| TCP | 443 | 10.0.1.10/32 | HTTPS (только с edge IP) |
| ANY | - | 10.0.1.0/24 | Всё внутри подсети (inter-team) |
| ICMP | - | 10.0.1.0/24 | Ping from edge |

**Egress:**
| Протокол | Порт | Назначение | Описание |
|----------|------|------------|----------|
| ANY | - | 0.0.0.0/0 | All outbound (через edge) |

---

## Потоки данных

### Ingress Flow (HTTP/HTTPS)

```
User Browser -> DNS (*.south.aitalenthub.ru) -> Edge Public IP
  -> Traefik (:443, HTTPS termination) -> Team VM (:80, HTTP)
```

**Описание (HTTPS):**
1. Пользователь запрашивает DNS для `team01.south.aitalenthub.ru`
2. DNS возвращает публичный IP edge VM
3. Пользователь отправляет HTTPS запрос на edge VM
4. Traefik принимает запрос на порту 443, расшифровывает TLS (сертификат Let's Encrypt, ACME HTTP-01)
5. Traefik определяет целевую VM по Host header
6. Traefik проксирует запрос на Team VM:80 по **HTTP** (без шифрования внутри подсети)
7. Ответ возвращается пользователю

**Описание (HTTP):**
1. Пользователь запрашивает DNS для `team01.south.aitalenthub.ru`
2. DNS возвращает публичный IP edge VM
3. Пользователь отправляет HTTP запрос на edge VM:80
4. Traefik принимает запрос на порту 80 и редиректит на HTTPS
5. Далее по HTTPS flow выше

**Важно:**
- SSL-сертификат выдаётся и хранится на **edge VM** (Let's Encrypt, ACME HTTP-01), команды не занимаются получением сертификатов
- Трафик от edge до team VM идёт по HTTP на порт 80 -- Nginx/Certbot на team VM не нужны
- Для кастомных доменов нужно явно добавить правило в Traefik конфигурацию

### Egress Flow (Outbound Traffic)

```
Team VM -> iptables mangle (TPROXY) -> Xray routing rules
  -> AI API? -> Proxy server -> AI API
  -> Regular traffic? -> NAT (MASQUERADE) -> Internet
```

**Описание:**

1. **Team VM отправляет пакет** (например, к `api.openai.com`)
2. **TPROXY перехватывает** пакет через iptables mangle
3. **Policy routing** направляет пакет на loopback с fwmark=1
4. **Xray dokodemo-door** принимает пакет на порту 12345
5. **Xray проверяет routing правила:**
   - Если домен/IP совпадает с geosite:category-ai -> **proxy**
   - Если обычный трафик -> **direct**
6. **Proxy:** Пакет шифруется и отправляется через Shadowsocks/VLESS
7. **Direct:** Пакет проходит через NAT MASQUERADE напрямую
8. Ответ возвращается обратно

### SSH Flow (Jump Host)

```
User Laptop -> SSH to jump@bastion -> ProxyJump -> teamXX@10.0.1.X
```

**Описание:**
1. Пользователь подключается к bastion с ключом `{team_id}-key`
2. SSH ProxyJump автоматически открывает туннель
3. Второе SSH соединение через туннель к Team VM с тем же ключом `{team_id}-key`
4. Пользователь получает интерактивную сессию на Team VM

**AllowTcpForwarding:** Должен быть включен на bastion для ProxyJump.

---

## Security

### Принципы безопасности

1. **Network Isolation**
   - Team VMs без публичного IP, только приватные адреса в 10.0.1.0/24
   - Доступ только через bastion (SSH) и Traefik (HTTP/HTTPS)

2. **Minimal Attack Surface**
   - Edge VM -- единственная точка входа
   - Security groups ограничивают доступ (CIDR-based)

3. **HTTPS Termination на edge**
   - Traefik расшифровывает TLS на edge VM, сертификат Let's Encrypt
   - Трафик внутри подсети (edge → team VM) по HTTP:80 — доверенная изолированная сеть

4. **SSH Key Authentication**
   - Пароли отключены
   - Уникальные ключи для каждой команды

5. **Audit Trail**
   - Логи SSH подключений
   - Логи HTTP/HTTPS запросов (Traefik)
   - Логи proxy трафика (Xray)

### SSH Ключи

Для каждой команды генерируется **1 пара ключей** (`{team_id}-key`, ED25519).

Один ключ используется как для bastion jump (с ограничением `permitopen` на edge VM), так и для прямого входа на Team VM. Публичный ключ прописывается на edge VM (в `/home/jump/.ssh/authorized_keys`) и на Team VM (в `/home/<user>/.ssh/authorized_keys`).

### Security Groups Flow

```
Internet
   |
   +-> :22, :80, :443 -> Edge VM (allowed)
   |
   +-> Any other port -> Edge VM (denied)

Edge VM
   |
   +-> :22, :80, :443 -> Team VM (allowed)
   |
   +-> Any other port -> Team VM (denied)

Team VM
   |
   +-> All ports -> Edge VM -> Internet (allowed)
```

---

## Масштабирование

### Добавление новой команды

1. **Обновить `terraform.tfvars`:**
   ```hcl
   teams = {
     "team01" = { user = "team01", public_keys = [], ip = "10.0.1.11" }
     "team02" = { user = "team02", public_keys = [], ip = "10.0.1.12" }
     "team03" = { user = "team03", public_keys = [], ip = "10.0.1.13" }  # новая
   }
   ```

2. **Применить изменения:**
   ```bash
   cd environments/dev
   terraform apply

   cd ../../ansible
   ansible-playbook playbooks/team-vms.yml
   ```

3. **Terraform создаст:**
   - Новую VM в подсети 10.0.1.0/24
   - SSH ключи в `secrets/team-team03/`
   - Обновленный Ansible inventory

4. **Ansible настроит:**
   - Базовые пакеты
   - Docker

5. **Настроить DNS:**
   ```
   team03.south.aitalenthub.ru  A  <edge-public-ip>
   ```

**Время развертывания:** ~3-5 минут (Terraform) + ~2-3 минуты (Ansible).

### Удаление команды

1. **Удалить из `terraform.tfvars`**
2. **Применить изменения:** `terraform apply`
3. **Terraform удалит:**
   - VM команды
   - SSH ключи из secrets

**Внимание:** Данные на VM будут потеряны. Сделайте backup перед удалением.

### Вертикальное масштабирование

Для изменения ресурсов VM (CPU/RAM/Disk):

**В `terraform.tfvars`:**
```hcl
team_cores       = 8      # было 4
team_memory      = 16     # было 8
team_disk_size   = 100    # было 65
```

**Внимание:** Это пересоздаст VM. Данные будут потеряны.

### Горизонтальное масштабирование

**Текущие ограничения:**
- Одна команда = одна VM
- Нет load balancing между VM

**Возможное расширение:**
- Multiple VMs per team
- Internal load balancer
- Shared storage (NFS/Ceph)

---

## Мониторинг

### Доступные метрики

**Edge VM:**
- CPU, RAM, Disk usage
- Network traffic (in/out)
- Количество SSH подключений
- Количество HTTP requests (Traefik)
- Proxy traffic volume (Xray)

**Team VM:**
- CPU, RAM, Disk usage
- Network traffic (in/out)
- Running processes

### Логи

**Расположения:**
- Traefik: `docker logs traefik`
- Xray: `sudo journalctl -u xray`
- System: `/var/log/syslog`, `journalctl`

---

## Limitations

**Текущие ограничения:**

1. **Single region:** Cloud.ru Evolution (ru.AZ-1)
2. **No HA:** Single edge VM (single point of failure)
3. **No auto-scaling:** Fixed number of VMs
4. **No shared storage:** Each VM has isolated filesystem
5. **Manual DNS:** DNS records нужно настраивать вручную
6. **No route table resource:** Статические маршруты настраиваются на VM

**Возможные улучшения:**
- Multi-AZ deployment
- Load balancer перед edge VM
- Auto-scaling для team VMs
- Shared storage (NFS, Ceph)
- Automatic DNS management (External DNS)

---

## Cloud.ru Evolution Специфика

- **Нет VPC ресурса** -- подсети создаются как top-level ресурсы
- **Нет route table ресурса** -- статические маршруты настраиваются на VM через Ansible
- **Security group rules** задаются inline (`rules {}` блоки), источник -- CIDR (`remote_ip_prefix`)
- **Все ресурсы** требуют `availability_zone` блок
- **Имена подсетей** должны быть >= 7 символов
- **Формат портов:** `"from:to"` или `"any"`
- **Compute image block** задает hostname, username, SSH key (нет поддержки user_data)

---

## См. также

- [modules.md](modules.md) - детальное описание Terraform модулей и Ansible ролей
- [admin-guide.md](admin-guide.md) - руководство администратора
- [user-guide.md](user-guide.md) - руководство пользователя
