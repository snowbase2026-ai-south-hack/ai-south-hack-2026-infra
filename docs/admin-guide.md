# Руководство администратора

> **Последнее обновление:** 2026-03-17
> **Связанные документы:** [architecture.md](architecture.md), [xray-configuration.md](xray-configuration.md), [modules.md](modules.md)

## Обзор

Это руководство для администраторов, управляющих инфраструктурой AI Talent Camp через Terraform и Ansible. Инфраструктура развертывается на Cloud.ru Evolution.

**Двухуровневая модель:**
- **Terraform** -- провизионинг VM, сетей, security groups, генерация SSH-ключей
- **Ansible** -- вся постнастройка: Docker, Traefik, Xray, NAT, iptables

---

## Содержание

- [Prerequisites](#prerequisites)
- [Настройка Cloud.ru Evolution](#настройка-cloudru-evolution)
- [Развертывание инфраструктуры](#развертывание-инфраструктуры)
- [Управление командами](#управление-командами)
- [Конфигурация Xray](#конфигурация-xray)
- [Конфигурация Traefik](#конфигурация-traefik)
- [Мониторинг](#мониторинг)
- [Backup и восстановление](#backup-и-восстановление)

---

## Prerequisites

### Обязательные инструменты

#### Terraform >= 1.0

```bash
# Установка на Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Проверка
terraform version
```

#### Ansible (ansible-core >= 2.20)

```bash
# Установка через pip
pip install ansible-core

# Или через пакетный менеджер
sudo apt install ansible

# Проверка
ansible --version
```

#### SSH клиент

Обычно предустановлен на Linux/macOS. Для Windows используйте WSL или Git Bash.

### Опциональные инструменты

```bash
# jq - для работы с JSON
sudo apt install jq

# yq - для работы с YAML
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq
```

---

## Настройка Cloud.ru Evolution

### 1. Получение учетных данных

В консоли Cloud.ru (console.cloud.ru):

1. Создайте проект (или используйте существующий)
2. Перейдите в **Service accounts** -> **Keys**
3. Создайте API-ключ (auth_key_id + auth_secret)
4. Скопируйте **project_id** из URL проекта

### 2. Провайдер Terraform

Провайдер Cloud.ru Evolution (`cloud.ru/cloudru/cloud` v1.6.0) устанавливается через filesystem mirror. Авторизация через переменные:

- `project_id` -- ID проекта
- `auth_key_id` -- ID ключа сервисного аккаунта
- `auth_secret` -- секрет ключа

---

## Развертывание инфраструктуры

### 1. Клонирование репозитория

```bash
git clone https://github.com/AI-Talent-Camp-2026/ai-talent-camp-2026-infra.git
cd ai-talent-camp-2026-infra
```

### 2. Настройка переменных

```bash
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Отредактируйте `terraform.tfvars`:

```hcl
# Cloud.ru Evolution (обязательно)
project_id  = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
auth_key_id = ""
auth_secret = ""

# SSH ключ администратора (обязательно)
jump_public_key = "ssh-ed25519 AAAA... admin@example.com"

# Сетевые настройки (можно оставить по умолчанию)
public_cidr  = "10.0.1.0/24"
private_cidr = "10.0.2.0/24"

# Начальное развертывание - без команд
teams = {}
```

### 3. Поэтапное развертывание

Рекомендуется развертывать инфраструктуру поэтапно.

#### Phase 1: Terraform -- базовая инфраструктура

```bash
cd environments/dev

# Инициализация Terraform
terraform init

# Проверка плана
terraform plan

# Применение
terraform apply
```

**Создается:**
- Public и private subnets (без VPC ресурса -- в Cloud.ru Evolution подсети создаются напрямую)
- Security groups
- Edge/NAT VM с floating IP и двумя сетевыми интерфейсами

**Время:** ~5 минут

#### Phase 2: Ansible -- настройка edge VM

После `terraform apply` автоматически генерируется Ansible inventory в `ansible/inventory/hosts.yml`.

```bash
cd ../../ansible

# Настроить edge VM (Docker, NAT, Traefik, Xray)
ansible-playbook playbooks/edge.yml
```

Ansible установит и настроит:
- Общие пакеты (curl, wget, htop, jq, unzip, net-tools)
- Docker + Docker Compose
- NAT (iptables MASQUERADE + hairpin NAT + ip_forward)
- Traefik (Docker-контейнер с host networking)
- Xray (systemd-сервис с TPROXY)

**Проверка:**
```bash
# Получить публичный IP
cd ../environments/dev
terraform output edge_public_ip

# Проверить SSH доступ
ssh jump@<edge-public-ip>

# Проверить Traefik
ssh jump@<edge-public-ip> "docker ps | grep traefik"

# Проверить Xray
ssh jump@<edge-public-ip> "sudo systemctl status xray"
```

#### Phase 3: Тестовая команда

Добавьте одну команду для тестирования:

```hcl
# terraform.tfvars
teams = {
  "team01" = {
    user        = "team01"
    public_keys = []
    ip          = "10.0.2.11"
  }
}
```

```bash
cd environments/dev
terraform apply
```

**Создается:**
- Team VM в private subnet со статическим IP 10.0.2.11
- SSH ключи в `secrets/team-team01/` (папки именуются `secrets/team-<ключ_из_teams>/`)
- Ansible inventory обновляется автоматически

Затем настройте team VM через Ansible:

```bash
cd ../../ansible
ansible-playbook playbooks/team-vms.yml
```

Ansible установит на team VM:
- Общие пакеты
- Docker + Docker Compose

**Проверка:**
```bash
# Проверить VM создана
terraform output team_vms

# Проверить SSH подключение
ssh -F ../../secrets/team-team01/ssh-config team01

# На team VM проверить интернет
curl ifconfig.co
```

#### Phase 4: Остальные команды

Добавляйте команды по мере регистрации:

```hcl
teams = {
  "team01"    = { user = "team01",    public_keys = [], ip = "10.0.2.11" }
  "team02"    = { user = "team02",    public_keys = [], ip = "10.0.2.12" }
  "team03"    = { user = "team03",    public_keys = [], ip = "10.0.2.13" }
  "dashboard" = { user = "dashboard", public_keys = [], ip = "10.0.2.100" }
}
```

```bash
cd environments/dev
terraform apply

cd ../../ansible
ansible-playbook playbooks/team-vms.yml
```

Terraform создаст только новые VM, не трогая существующие.

### 4. Настройка DNS

После развертывания настройте DNS записи:

```bash
# Получить публичный IP edge
EDGE_IP=$(cd environments/dev && terraform output -raw edge_public_ip)

echo "Добавьте DNS записи:"
echo "*.south.aitalenthub.ru     A  $EDGE_IP"
echo "bastion.south.aitalenthub.ru  A  $EDGE_IP"
```

В вашем DNS провайдере добавьте:

```
*.south.aitalenthub.ru        A    <edge-public-ip>
bastion.south.aitalenthub.ru  A    <edge-public-ip>
```

**Проверка DNS:**
```bash
dig team01.south.aitalenthub.ru
dig bastion.south.aitalenthub.ru
```

---

## Управление командами

### Добавление новой команды

1. **Обновить terraform.tfvars:**
   ```hcl
   teams = {
     "team01" = { user = "team01", public_keys = [], ip = "10.0.2.11" }
     "team02" = { user = "team02", public_keys = [], ip = "10.0.2.12" }
     "team03" = { user = "team03", public_keys = [], ip = "10.0.2.13" }  # новая
   }
   ```

2. **Применить изменения:**
   ```bash
   cd environments/dev
   terraform apply

   cd ../../ansible
   ansible-playbook playbooks/team-vms.yml
   ```

3. **Получить credentials:**
   ```bash
   # Credentials создаются в:
   ls -la ../../secrets/team-team03/

   # Передать папку команде
   zip -r team03.zip ../../secrets/team-team03/
   ```

4. **Настроить DNS** (если не используется wildcard):
   ```
   team03.south.aitalenthub.ru  A  <edge-public-ip>
   ```

### Удаление команды

**Внимание:** Данные на VM будут потеряны!

1. **Backup данных** (если нужно):
   ```bash
   ssh -F ~/.ssh/ai-camp/ssh-config team03 "tar czf ~/backup.tar.gz ~/workspace"
   scp -F ~/.ssh/ai-camp/ssh-config team03:~/backup.tar.gz ./team03-backup.tar.gz
   ```

2. **Удалить из terraform.tfvars:**
   ```hcl
   teams = {
     "team01" = { user = "team01", public_keys = [], ip = "10.0.2.11" }
     "team02" = { user = "team02", public_keys = [], ip = "10.0.2.12" }
     # "team03" - удалена
   }
   ```

3. **Применить изменения:**
   ```bash
   terraform apply
   ```

### Изменение ресурсов VM

**В terraform.tfvars:**

```hcl
# Для всех team VMs
team_cores      = 8      # было 4
team_memory     = 16     # было 8
team_disk_size  = 100    # было 65
```

**Внимание:** Это пересоздаст все team VMs. Сделайте backup!

---

## Конфигурация Xray

Подробнее см. [xray-configuration.md](xray-configuration.md).

### Обновление конфигурации через Ansible (рекомендованный способ)

Xray настраивается через Ansible-роль `xray`. Конфигурация генерируется из Jinja2-шаблона `ansible/roles/xray/templates/config.json.j2` и переменных в `ansible/group_vars/`.

```bash
# 1. Отредактировать переменные
nano ansible/group_vars/edge.yml

# 2. Применить через Ansible
cd ansible
ansible-playbook playbooks/edge.yml --tags xray
```

Ansible автоматически:
- Развернет обновленный конфиг в `/etc/xray/config.json`
- Перезапустит Xray сервис

### Изменение proxy сервера

При смене proxy сервера нужно обновить параметры в Ansible-переменных и запустить playbook.

### Редактирование напрямую на edge VM

Для быстрых изменений без Ansible:

```bash
# Подключиться к edge VM
ssh jump@<edge-ip>

# Отредактировать конфигурацию
sudo nano /etc/xray/config.json

# Перезапустить Xray
sudo systemctl restart xray

# Проверить статус
sudo systemctl status xray
sudo journalctl -u xray --no-pager -n 20
```

**Внимание:** Изменения, сделанные напрямую на VM, будут перезаписаны при следующем запуске `ansible-playbook`.

---

## Конфигурация Traefik

### Статическая конфигурация

Находится в Ansible-шаблоне `ansible/roles/traefik/templates/traefik.yml.j2`. Развертывается в `/etc/traefik/traefik.yml` на edge VM.

### Динамическая конфигурация

Генерируется автоматически через Ansible-шаблон `ansible/roles/traefik/templates/dynamic.yml.j2`. Развертывается в `/etc/traefik/dynamic/teams.yml`.

**Формат:**
```yaml
tcp:
  routers:
    team01:
      entryPoints: ["websecure"]
      rule: "HostSNI(`team01.south.aitalenthub.ru`)"
      service: "team01"
      tls:
        passthrough: true
  services:
    team01:
      loadBalancer:
        servers:
          - address: "10.0.2.11:443"
```

При добавлении новой команды конфиг обновляется через `ansible-playbook playbooks/edge.yml`.

### Добавление кастомных доменов

Когда команда запрашивает использование собственного домена (например, `app.mydomain.com`), нужно добавить его в Traefik конфигурацию.

**Шаг 1: Получить запрос**

Команда должна создать issue с информацией:
- Номер команды (например, team01)
- Кастомный домен (например, app.mydomain.com)
- Тип: HTTP и/или HTTPS

**Шаг 2: Обновить динамическую конфигурацию**

Отредактируйте Ansible-шаблон или непосредственно `/etc/traefik/dynamic/teams.yml` на edge VM:

**Для HTTPS (TLS Passthrough):**
```yaml
tcp:
  routers:
    team01-router:
      entryPoints:
        - websecure
      # Добавить кастомный домен через ||
      rule: "HostSNI(`team01.south.aitalenthub.ru`) || HostSNI(`app.mydomain.com`)"
      service: team01-service
      tls:
        passthrough: true
```

**Для HTTP:**
```yaml
http:
  routers:
    team01-http:
      entryPoints:
        - web
      # Добавить кастомный домен через ||
      rule: "Host(`team01.south.aitalenthub.ru`) || Host(`app.mydomain.com`)"
      service: team01-http-service
```

**Шаг 3: Применить изменения**

```bash
# Через Ansible
cd ansible
ansible-playbook playbooks/edge.yml --tags traefik

# Или вручную на edge VM
ssh jump@bastion.south.aitalenthub.ru
docker restart traefik
```

**Шаг 4: Проверка**

```bash
# Проверить логи Traefik
docker logs traefik | grep -i "app.mydomain.com"
```

**Шаг 5: Уведомить команду**

Сообщите команде, что домен добавлен. Команда должна:
1. Настроить DNS (CNAME или A-запись)
2. Обновить Nginx на своей VM
3. Получить SSL сертификат

---

## Мониторинг

### Проверка статуса компонентов

```bash
# SSH к edge VM
ssh jump@bastion.south.aitalenthub.ru

# Traefik
docker ps | grep traefik
docker logs traefik --tail 50

# Xray
sudo systemctl status xray
sudo journalctl -u xray -n 50

# System resources
htop
df -h
free -m
```

### Логи

**Расположения:**
- Traefik: `docker logs traefik`
- Xray: `sudo journalctl -u xray`
- System: `journalctl -f`

**Полезные команды:**
```bash
# Мониторинг Xray в реальном времени
sudo journalctl -u xray -f

# Статистика
htop
```

---

## Backup и восстановление

### Backup конфигурации

```bash
# Backup всех secrets
tar czf ai-camp-backup-$(date +%Y%m%d).tar.gz secrets/

# Backup Terraform state
cp environments/dev/terraform.tfstate terraform.tfstate.backup
```

### Backup данных команд

```bash
# Для каждой команды
for team in team01 team02 team03; do
  ssh -F ~/.ssh/ai-camp/ssh-config ${team} \
    "tar czf ~/team-backup.tar.gz ~/workspace"
  scp -F ~/.ssh/ai-camp/ssh-config \
    ${team}:~/team-backup.tar.gz \
    ./${team}-backup-$(date +%Y%m%d).tar.gz
done
```

### Восстановление

```bash
# Восстановить secrets
tar xzf ai-camp-backup-YYYYMMDD.tar.gz

# Восстановить Terraform state (если необходимо)
cp terraform.tfstate.backup environments/dev/terraform.tfstate

# Применить конфигурацию
cd environments/dev
terraform apply

# Настроить серверы через Ansible
cd ../../ansible
ansible-playbook playbooks/site.yml
```

---

## Полезные команды

### Terraform

```bash
# Все команды из environments/dev
cd environments/dev

# Форматирование (обязательно перед коммитом)
terraform fmt -recursive

# Валидация
terraform init
terraform validate

# Посмотреть текущее состояние
terraform show

# Получить outputs
terraform output

# Посмотреть state для ресурса
terraform state show module.edge.cloudru_evolution_compute.edge
```

### Ansible

```bash
cd ansible

# Полная настройка всех серверов
ansible-playbook playbooks/site.yml

# Только edge VM
ansible-playbook playbooks/edge.yml

# Только team VMs
ansible-playbook playbooks/team-vms.yml

# Обновить только Xray
ansible-playbook playbooks/edge.yml --tags xray

# Обновить только Traefik
ansible-playbook playbooks/edge.yml --tags traefik
```

### Диагностика

```bash
# Проверить connectivity между edge и team VM
ssh jump@bastion.south.aitalenthub.ru "ping -c 3 10.0.2.11"

# Проверить NAT работает
ssh -F ~/.ssh/ai-camp/ssh-config team01 "curl -s ifconfig.co"

# Проверить TPROXY активность
ssh jump@bastion.south.aitalenthub.ru \
  "sudo iptables -t mangle -L XRAY -n -v | grep TPROXY"
```

---

## Удаление инфраструктуры

**Внимание:** Это удалит **ВСЕ** ресурсы включая данные на VM!

### Полное удаление

```bash
cd environments/dev

# Backup перед удалением
terraform output -json > outputs-backup.json

# Удалить все ресурсы
terraform destroy
```

### Выборочное удаление

```bash
# Удалить конкретную team VM
terraform destroy -target='module.team_vm.cloudru_evolution_compute.team["team03"]'

# Удалить credentials команды
rm -rf ../../secrets/team-team03/
```

---

## Управление прозрачным проксированием

### Проверка NAT и TPROXY

#### Проверка исходящего трафика

```bash
# Проверить внешний IP (должен быть IP edge VM)
curl ifconfig.co

# Проверить доступ к интернету
curl -I https://google.com

# Проверить DNS
nslookup google.com
```

#### Проверка маршрутов

```bash
# Посмотреть таблицу маршрутизации
ip route

# Должен быть маршрут через edge VM:
# default via 10.0.1.x dev eth0
```

#### Проверка TPROXY (прозрачное проксирование)

TPROXY автоматически перехватывает трафик и маршрутизирует через VLESS proxy:

```bash
# Проверить, что AI API идут через proxy
curl -v https://api.openai.com/v1/models

# Проверить YouTube (тоже через proxy)
curl -I https://www.youtube.com

# Обычные сайты идут напрямую
curl -I https://google.com
```

**Важно:** Весь трафик из private subnet автоматически перехватывается на edge VM и маршрутизируется по правилам Xray.

#### Что идёт через VLESS proxy

- AI APIs (OpenAI, Anthropic, Google AI, Groq, Mistral и др.)
- Соцсети (YouTube, Instagram, TikTok, LinkedIn, Telegram, Notion)
- Остальной трафик идёт напрямую (direct)

### Управление Traefik routing

#### Как работает маршрутизация

```
Internet -> Edge VM (Traefik) -> Team VM
                  |
                  +-- team01.south.aitalenthub.ru -> Team01 VM:80/443
                  +-- team02.south.aitalenthub.ru -> Team02 VM:80/443
                  +-- ...
```

#### TLS Passthrough

Traefik настроен в режиме TLS passthrough - SSL-терминация происходит на team VM.

Это означает:
1. Traefik не расшифровывает трафик
2. Сертификат должен быть на team VM
3. Полная end-to-end шифрование

### Управление конфигурацией Xray

#### Как работает Xray

Xray запущен на edge VM как systemd сервис и обеспечивает прозрачное проксирование (TPROXY):
- Перехватывает TCP/UDP трафик из private subnet
- Маршрутизирует по правилам: AI APIs и соцсети через VLESS proxy, остальное напрямую
- Конфигурация: `/etc/xray/config.json`
- Бинарный файл: `/usr/local/share/xray/xray`

#### Изменение конфигурации Xray

##### Вариант 1: Через Ansible (рекомендуется)

Отредактируйте переменные в `ansible/group_vars/edge.yml` и/или шаблон `ansible/roles/xray/templates/config.json.j2`, затем примените:

```bash
cd ansible
ansible-playbook playbooks/edge.yml --tags xray
```

##### Вариант 2: Редактирование напрямую на edge VM

Для быстрых изменений без Ansible:

```bash
# Подключиться к edge VM
ssh jump@<edge-ip>

# Отредактировать конфигурацию
sudo nano /etc/xray/config.json

# Перезапустить Xray
sudo systemctl restart xray

# Проверить статус
sudo systemctl status xray
sudo journalctl -u xray --no-pager -n 20
```

**Внимание:** Изменения, сделанные напрямую на VM, будут перезаписаны при следующем запуске Ansible.

#### Изменение routing правил

Routing правила находятся в секции `routing.rules` конфигурации Xray.

##### Добавить домен через proxy

```json
{
  "type": "field",
  "domain": [
    "geosite:category-ai-!cn",
    "geosite:youtube",
    "domain:example.com",
    "full:api.example.com"
  ],
  "outboundTag": "proxy"
}
```

##### Добавить домен напрямую (bypass proxy)

```json
{
  "type": "field",
  "domain": ["domain:mysite.ru"],
  "outboundTag": "direct"
}
```

##### Блокировать домен

```json
{
  "type": "field",
  "domain": ["domain:blocked.com"],
  "outboundTag": "block"
}
```

#### Отключение TPROXY (только NAT)

Если нужно временно отключить прозрачное проксирование:

```bash
# На edge VM
sudo iptables -t mangle -D PREROUTING -s 10.0.2.0/24 -j XRAY
sudo systemctl stop xray
```

Трафик будет идти напрямую через NAT (MASQUERADE).

Для включения обратно:
```bash
sudo systemctl start xray
sudo iptables -t mangle -A PREROUTING -s 10.0.2.0/24 -j XRAY
```

#### Диагностика Xray

```bash
# Проверить статус Xray
sudo systemctl status xray

# Смотреть логи в реальном времени
sudo journalctl -u xray -f

# Проверить конфигурацию (валидность JSON)
/usr/local/share/xray/xray run -test -config /etc/xray/config.json
```

### Диагностика инфраструктуры

#### VM не имеет доступа в интернет

1. Проверить маршрут:
   ```bash
   ip route | grep default
   ```

2. Проверить NAT на edge:
   ```bash
   # На edge VM
   sudo iptables -t nat -L -n -v | grep MASQUERADE
   ```

3. Проверить security group

#### Не работает SSH через jump-host

1. Проверить доступ к bastion:
   ```bash
   ssh -v jump@bastion.south.aitalenthub.ru
   ```

2. Проверить ключи:
   ```bash
   ssh-add -l
   ls -la ~/.ssh/ai-camp/
   ```

#### TPROXY не работает

1. Проверить Xray сервис запущен:
   ```bash
   # На edge VM
   sudo systemctl status xray
   sudo journalctl -u xray -f
   ```

2. Проверить iptables правила:
   ```bash
   # На edge VM
   sudo iptables -t mangle -L PREROUTING -n -v
   sudo iptables -t mangle -L XRAY -n -v
   ```

3. Проверить policy routing:
   ```bash
   # На edge VM
   ip rule show
   ip route show table 100
   ```

---

## Troubleshooting

Для решения проблем см. [troubleshooting.md](troubleshooting.md).

**Быстрые проверки:**

```bash
# Terraform не может подключиться к Cloud.ru
terraform init

# State locked
terraform force-unlock <lock-id>

# Модуль не найден
terraform init -upgrade
```

---

## См. также

- [architecture.md](architecture.md) - архитектура инфраструктуры
- [xray-configuration.md](xray-configuration.md) - конфигурация Xray
- [modules.md](modules.md) - документация Terraform модулей
- [troubleshooting.md](troubleshooting.md) - решение проблем
- [development.md](development.md) - для разработчиков
