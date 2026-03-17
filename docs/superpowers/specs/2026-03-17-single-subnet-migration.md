# Миграция на одну подсеть + TPROXY

**Дата:** 2026-03-17
**Статус:** Черновик

## Контекст

Двух-подсетевая архитектура (public 10.0.1.0/24 + private isolated 10.0.2.0/24) не работает в Cloud.ru Evolution:
- Приватная подсеть изолированная (не в VPC) — нет маршрутизации между подсетями
- Dual-interface на edge VM: конфликты DHCP, проблемы с primary, `interface_security_enabled` несовместим с SG, интерфейсы после создания в состоянии DOWN
- Cloud.ru Evolution не имеет ресурса route table

**Решение:** одна подсеть в VPC Default по паттерну Cloud.ru VM-router. Edge без SG (`interface_security_enabled=false` для TPROXY/NAT), защита через iptables (Ansible). Team VMs меняют default route на edge.

## Ключевые решения

| Вопрос | Решение | Обоснование (Cloud.ru) |
|--------|---------|----------------------|
| Подсеть | Одна `10.0.1.0/24`, `routed_network=true` | VM-router pattern, internet gateway через VPC Default |
| Edge IP | `10.0.1.10` (статический) | `ip_address` в `network_interfaces` |
| Team IPs | `10.0.1.x` (dashboard=10.0.1.100) | `ip_address` в `network_interfaces` |
| Edge SG | Нет — `interface_security_enabled=false` | Провайдер запрещает SG при `interface_security_enabled=false` |
| Team SG | Да — SSH/HTTP/HTTPS от edge IP, inter-team от subnet | CIDR-based `remote_ip_prefix` (единственный способ) |
| NAT | MASQUERADE на edge | `ip_forward=1` + `interface_security_enabled=false` отключает src/dst check |
| Team routing | Default gateway: 10.0.1.10 (netplan override, заменяет DHCP gateway 10.0.1.1) | Нет route table resource — маршруты через netplan |
| Edge firewall | iptables INPUT/FORWARD (Ansible) | Замена SG на edge |

### Предварительная верификация: FIP + interface_security_enabled=false

Ключевое предположение плана: Cloud.ru Evolution позволяет FIP на интерфейсе с `interface_security_enabled=false`. В текущем коде FIP прикреплён к интерфейсу с security enabled, а `interface_security_enabled=false` — на отдельном интерфейсе.

**Перед началом реализации** создать тестовую VM с одним интерфейсом (FIP + `interface_security_enabled=false`). Если API отклоняет эту комбинацию:

**Fallback**: два интерфейса на ОДНОЙ подсети:
- Интерфейс 1: `subnet_name`, SG (permissive), FIP, `interface_security_enabled=true`
- Интерфейс 2: `subnet_name`, `ip_address=10.0.1.10`, `interface_security_enabled=false` (NAT)

## Dataflow после миграции

```
Team VM (10.0.1.100)
  default gw → 10.0.1.10 (edge, same L2 subnet)
    → edge ip_forward + MASQUERADE → 10.0.1.1 (VPC gateway) → internet
    → edge Xray TPROXY → VLESS → AI APIs

Internet → FIP 176.109.104.2
  → edge Traefik → team VMs (10.0.1.x)
```

## Реализация

### Фаза 1: Terraform (шаги 1-8)

#### Шаг 1: `modules/network/` — одна подсеть

**variables.tf**: `public_cidr`, `private_cidr` → `subnet_cidr` (default "10.0.1.0/24")

**main.tf**: удалить `cloudru_evolution_subnet.private`, переименовать `.public` → `.main`:
```hcl
resource "cloudru_evolution_subnet" "main" {
  name            = "${var.project_name}-subnet"  # >= 7 символов
  subnet_address  = var.subnet_cidr
  default_gateway = cidrhost(var.subnet_cidr, 1)
  routed_network  = true
  availability_zone { id = var.availability_zone_id }
}
```

**outputs.tf**: 6 выходов → 3: `subnet_id`, `subnet_name`, `subnet_cidr`

#### Шаг 2: `modules/security/` — только team SG

**variables.tf**: `public_cidr`, `private_cidr` → `subnet_cidr`, `edge_private_ip`. Оставить `name`, `availability_zone_id` без изменений.

**main.tf**: удалить `cloudru_evolution_security_group.edge` целиком. Обновить team SG:
```hcl
resource "cloudru_evolution_security_group" "team" {
  name        = "${var.name}-team-sg"
  description = "Security group for team VMs"

  availability_zone {
    id = var.availability_zone_id
  }

  # SSH — только от edge
  rules {
    direction        = "ingress"
    ether_type       = "IPv4"
    ip_protocol      = "tcp"
    port_range       = "22:22"
    remote_ip_prefix = "${var.edge_private_ip}/32"
    description      = "SSH from edge"
  }

  # HTTP — только от edge (Traefik proxy)
  rules {
    direction        = "ingress"
    ether_type       = "IPv4"
    ip_protocol      = "tcp"
    port_range       = "80:80"
    remote_ip_prefix = "${var.edge_private_ip}/32"
    description      = "HTTP from edge"
  }

  # HTTPS — только от edge (Traefik proxy)
  rules {
    direction        = "ingress"
    ether_type       = "IPv4"
    ip_protocol      = "tcp"
    port_range       = "443:443"
    remote_ip_prefix = "${var.edge_private_ip}/32"
    description      = "HTTPS from edge"
  }

  # Inter-team: все протоколы внутри подсети (включая ICMP для ping между командами)
  rules {
    direction        = "ingress"
    ether_type       = "IPv4"
    ip_protocol      = "any"
    port_range       = "any"
    remote_ip_prefix = var.subnet_cidr
    description      = "All traffic within subnet"
  }

  # Egress — без ограничений
  rules {
    direction        = "egress"
    ether_type       = "IPv4"
    ip_protocol      = "any"
    port_range       = "any"
    remote_ip_prefix = "0.0.0.0/0"
    description      = "Allow all outbound traffic"
  }
}
```

> Отдельное правило ICMP убрано — правило `ip_protocol = "any"` от `subnet_cidr` уже покрывает ICMP.

**outputs.tf**: убрать `edge_sg_id`, оставить `team_sg_id`

#### Шаг 3: `modules/edge/` — один интерфейс, без SG

**variables.tf**: убрать `public_subnet_name`, `private_subnet_name`, `security_group_id`, `private_ip` → добавить `subnet_name`, `ip_address` (default "10.0.1.10")

**main.tf**: убрать второй `network_interfaces` блок. Единственный интерфейс:
```hcl
network_interfaces {
  subnet { name = var.subnet_name }
  ip_address                 = var.ip_address
  interface_security_enabled = false  # NAT/forward, запрещает SG
  fip { id = cloudru_evolution_fip.edge.id }
}
```

**outputs.tf**: `private_ip` → `value = var.ip_address`

#### Шаг 4: `modules/team_vm/`

**variables.tf**: `private_subnet_name` → `subnet_name`
**main.tf**: `var.private_subnet_name` → `var.subnet_name`

#### Шаг 5: `environments/dev/variables.tf`

Убрать `public_cidr`, `private_cidr` → `subnet_cidr` (default "10.0.1.0/24")

#### Шаг 6: `environments/dev/main.tf` — перепривязка модулей

```hcl
module "network" {
  subnet_cidr          = var.subnet_cidr
  # убрать public_cidr, private_cidr
}

module "security" {
  subnet_cidr      = var.subnet_cidr
  edge_private_ip  = cidrhost(var.subnet_cidr, 10)
  # убрать public_cidr, private_cidr
}

module "edge" {
  subnet_name = module.network.subnet_name
  ip_address  = cidrhost(var.subnet_cidr, 10)
  # убрать public_subnet_name, private_subnet_name, security_group_id, private_ip
}

module "team_vm" {
  subnet_name = module.network.subnet_name
  # убрать private_subnet_name
}
```

Ansible inventory templatefile: `edge_private_ip = module.edge.private_ip` — оставить как есть, output модуля edge уже вернёт новый IP.

#### Шаг 7: `environments/dev/outputs.tf`

Убрать `public_subnet_id`, `private_subnet_id` → `subnet_id = module.network.subnet_id`

#### Шаг 8: `environments/dev/terraform.tfvars.example`

```hcl
subnet_cidr = "10.0.1.0/24"
# убрать public_cidr, private_cidr

# teams example IPs → 10.0.1.x
# teams = {
#   "dashboard" = { user = "dashboard", public_keys = [], ip = "10.0.1.100" }
# }
```

### Фаза 2: Ansible (шаги 9-13)

#### Шаг 9: `ansible/group_vars/all.yml`

```yaml
---
domain: south.aitalenthub.ru
subnet_cidr: "10.0.1.0/24"
edge_private_ip: "10.0.1.10"
# убрать public_cidr, private_cidr
```

> `edge_public_ip` не добавлять в `all.yml` — он приходит из host_var в inventory (генерируется Terraform в `inventory.yml.tpl`). Гард `{% if edge_public_ip is defined %}` в iptables template обработает оба случая.

#### Шаг 10: `ansible/roles/nat/` — NAT + edge firewall (iptables-restore)

Вместо отдельных `iptables` модулей — Jinja2 шаблон + `iptables-restore`. Это атомарно и идемпотентно (повторный запуск не дублирует правила).

**tasks/main.yml**:
```yaml
---
- name: Enable IP forwarding
  sysctl:
    name: net.ipv4.ip_forward
    value: "1"
    state: present
    reload: true

- name: Install iptables-persistent
  apt:
    name: iptables-persistent
    state: present
  environment:
    DEBIAN_FRONTEND: noninteractive

- name: Deploy iptables rules
  template:
    src: iptables.rules.j2
    dest: /etc/iptables/rules.v4
    mode: "0644"
  notify: restore iptables
```

**handlers/main.yml**:
```yaml
---
- name: restore iptables
  shell: iptables-restore < /etc/iptables/rules.v4
```

**templates/iptables.rules.j2** (новый файл):
```
{% if xray_tproxy_enabled | default(false) %}
*mangle
:PREROUTING ACCEPT [0:0]

# === TPROXY (прозрачный прокси через Xray) ===
# Не перехватывать трафик от самого edge
-A PREROUTING -s {{ edge_private_ip }} -j RETURN
# Не перехватывать intra-subnet трафик (team↔team напрямую без Xray)
-A PREROUTING -s {{ subnet_cidr }} -d {{ subnet_cidr }} -j RETURN
# Не проксировать трафик к VLESS серверу (избежать loop)
{% if vless_server_ip is defined and vless_server_ip != "" %}
-A PREROUTING -d {{ vless_server_ip }} -j RETURN
{% endif %}
# TCP трафик team VMs → Xray TPROXY
-A PREROUTING -s {{ subnet_cidr }} -p tcp -j TPROXY --on-port {{ xray_tproxy_port }} --tproxy-mark 0x1/0x1
# DNS → Xray DNS handler
-A PREROUTING -s {{ subnet_cidr }} -p udp --dport 53 -j TPROXY --on-port 5353 --tproxy-mark 0x1/0x1

COMMIT
{% endif %}

*nat
:PREROUTING ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

# NAT MASQUERADE для трафика из подсети
-A POSTROUTING -s {{ subnet_cidr }} -j MASQUERADE

# Hairpin NAT: team VMs обращаются к edge public IP изнутри
{% if edge_public_ip is defined %}
-A PREROUTING -s {{ subnet_cidr }} -d {{ edge_public_ip }} -j DNAT --to-destination {{ edge_private_ip }}
-A POSTROUTING -s {{ subnet_cidr }} -d {{ edge_private_ip }} -j MASQUERADE
{% endif %}

COMMIT

*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# === INPUT (замена SG на edge) ===
-A INPUT -i lo -j ACCEPT
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
-A INPUT -p tcp --dport 80 -j ACCEPT
-A INPUT -p tcp --dport 443 -j ACCEPT
-A INPUT -s {{ subnet_cidr }} -j ACCEPT
-A INPUT -p icmp -j ACCEPT

# === FORWARD (NAT routing) ===
-A FORWARD -s {{ subnet_cidr }} -j ACCEPT
-A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

COMMIT
```

> Default policy: INPUT=DROP, FORWARD=DROP, OUTPUT=ACCEPT. Mangle table условен (`xray_tproxy_enabled`). `iptables-restore` атомарно заменяет все правила.

**defaults/main.yml**: обновить комментарий `private_cidr` → `subnet_cidr`

**tasks/main.yml** — добавить ip rule/route для TPROXY policy routing:
```yaml
- name: Add TPROXY ip rule
  command: ip rule add fwmark 1 table 100
  register: ip_rule_result
  changed_when: ip_rule_result.rc == 0
  failed_when: ip_rule_result.rc != 0 and 'File exists' not in ip_rule_result.stderr
  when: xray_tproxy_enabled | default(false)

- name: Add TPROXY local route
  command: ip route add local 0.0.0.0/0 dev lo table 100
  register: ip_route_result
  changed_when: ip_route_result.rc == 0
  failed_when: ip_route_result.rc != 0 and 'File exists' not in ip_route_result.stderr
  when: xray_tproxy_enabled | default(false)

- name: Persist TPROXY routing in rc.local
  copy:
    content: |
      #!/bin/bash
      ip rule add fwmark 1 table 100 2>/dev/null
      ip route add local 0.0.0.0/0 dev lo table 100 2>/dev/null
      exit 0
    dest: /etc/rc.local
    mode: "0755"
  when: xray_tproxy_enabled | default(false)

- name: Enable rc-local service
  systemd:
    name: rc-local
    enabled: true
  when: xray_tproxy_enabled | default(false)
```

#### Шаг 11: Team VMs — замена default route + DNS

Добавить `pre_tasks` в `ansible/playbooks/team-vms.yml`. Netplan через template (а не inline copy) — консистентно с проектным паттерном:

**ansible/roles/common/templates/90-route-override.yaml.j2** (новый файл):
```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
      routes:
        - to: default
          via: "{{ edge_private_ip }}"
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

**ansible/playbooks/team-vms.yml**:
```yaml
- name: Configure team VMs
  hosts: team_vms
  become: true
  pre_tasks:
    - name: Deploy netplan route override
      template:
        src: ../../roles/common/templates/90-route-override.yaml.j2
        dest: /etc/netplan/90-override.yaml
        mode: "0600"
      notify: apply netplan

    - name: Replace default route immediately
      shell: ip route replace default via {{ edge_private_ip }}
      changed_when: true

  handlers:
    - name: apply netplan
      command: netplan apply

  roles:
    - common
    - docker
```

#### Шаг 12: `ansible/roles/xray/` — TPROXY конфигурация

Xray конфиг — ручной секрет в `secrets/xray-config.json`. Ansible копирует готовый файл на edge.

**tasks/main.yml** (обновить):
```yaml
---
- name: Create Xray log directory
  file:
    path: /var/log/xray
    state: directory
    mode: "0755"

- name: Download Xray
  get_url:
    url: "https://github.com/XTLS/Xray-core/releases/download/v{{ xray_version }}/Xray-linux-64.zip"
    dest: /tmp/xray.zip
    mode: "0644"

- name: Create Xray directory
  file:
    path: /usr/local/share/xray
    state: directory
    mode: "0755"

- name: Extract Xray
  unarchive:
    src: /tmp/xray.zip
    dest: /usr/local/share/xray
    remote_src: true
  notify: restart xray

- name: Install libcap2-bin for setcap
  apt:
    name: libcap2-bin
    state: present

- name: Set CAP_NET_ADMIN for TPROXY
  command: setcap cap_net_admin+ep /usr/local/share/xray/xray
  changed_when: true

- name: Download geosite.dat
  get_url:
    url: "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
    dest: /usr/local/share/xray/geosite.dat
    mode: "0644"

- name: Download geoip.dat
  get_url:
    url: "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
    dest: /usr/local/share/xray/geoip.dat
    mode: "0644"

- name: Create Xray config directory
  file:
    path: /etc/xray
    state: directory
    mode: "0755"

- name: Deploy Xray config (from secrets/)
  copy:
    src: "{{ playbook_dir }}/../../secrets/xray-config.json"
    dest: /etc/xray/config.json
    mode: "0600"
  notify: restart xray

- name: Deploy Xray systemd service
  copy:
    content: |
      [Unit]
      Description=Xray Service
      After=network.target

      [Service]
      ExecStart=/usr/local/share/xray/xray run -config /etc/xray/config.json
      Restart=on-failure
      RestartSec=3
      # TPROXY requires NET_ADMIN
      AmbientCapabilities=CAP_NET_ADMIN

      [Install]
      WantedBy=multi-user.target
    dest: /etc/systemd/system/xray.service
    mode: "0644"
  notify:
    - reload systemd
    - restart xray

- name: Enable and start Xray
  systemd:
    name: xray
    state: started
    enabled: true
```

**group_vars/edge.yml** — добавить:
```yaml
xray_tproxy_enabled: true
xray_tproxy_port: 12345
vless_server_ip: ""  # IP VLESS-сервера для iptables mangle RETURN (заполнить вручную)
```

> Xray конфиг управляется вручную: пользователь редактирует `secrets/xray-config.json` и запускает `ansible-playbook playbooks/edge.yml` (или `update-services.yml`). Terraform не участвует в жизненном цикле xray конфига.

#### Шаг 13: `ansible/templates/inventory.yml.tpl`

Без структурных изменений — IP подставятся автоматически из Terraform. `vless_server_ip` берётся из `group_vars/edge.yml` (не из Terraform).

### Фаза 3: Terraform state + deploy (шаги 14-18)

#### Шаг 14: Удалить в Cloud.ru console

- VMs (edge, dashboard)
- Подсети (aicamp-public, aicamp-private)
- Security groups (aicamp-edge-sg, aicamp-team-sg)
- **FIP оставить** (176.109.104.2)

#### Шаг 15: Очистка terraform state

```bash
terraform state rm module.network.cloudru_evolution_subnet.public
terraform state rm module.network.cloudru_evolution_subnet.private
terraform state rm module.edge.cloudru_evolution_compute.edge
terraform state rm module.edge.cloudru_evolution_fip.edge
terraform state rm module.security.cloudru_evolution_security_group.edge
terraform state rm module.security.cloudru_evolution_security_group.team
terraform state rm 'module.team_vm.cloudru_evolution_compute.team["dashboard"]'
# Повторить для каждой команды в state (terraform state list | grep team_vm)
```

#### Шаг 16: Обновить terraform.tfvars

```hcl
subnet_cidr = "10.0.1.0/24"
# Team IPs → 10.0.1.x (dashboard = "10.0.1.100")
# Убрать public_cidr, private_cidr
```

#### Шаг 17: Import FIP

```bash
terraform import 'module.edge.cloudru_evolution_fip.edge' 345fb881-04ee-4f87-9ea9-fd985dda835a
```

#### Шаг 18: Deploy

```bash
cd environments/dev
terraform fmt -recursive
terraform validate
terraform plan
terraform apply

cd ../../ansible
ansible-playbook playbooks/site.yml
```

## Файлы для изменения

### Terraform (15 файлов):
- `modules/network/main.tf`, `variables.tf`, `outputs.tf`
- `modules/security/main.tf`, `variables.tf`, `outputs.tf`
- `modules/edge/main.tf`, `variables.tf`, `outputs.tf`
- `modules/team_vm/main.tf`, `variables.tf`
- `environments/dev/main.tf`, `variables.tf`, `outputs.tf`
- `environments/dev/terraform.tfvars.example`

### Ansible (11 файлов, 2 новых):
- `ansible/group_vars/all.yml` (subnet_cidr, edge_private_ip)
- `ansible/group_vars/edge.yml` (xray_tproxy_enabled, vless_server_ip)
- `ansible/roles/nat/tasks/main.yml` (iptables-restore + TPROXY ip rule/route)
- `ansible/roles/nat/handlers/main.yml` (restore вместо save)
- `ansible/roles/nat/defaults/main.yml` (комментарий: subnet_cidr)
- `ansible/roles/nat/templates/iptables.rules.j2` (новый — filter+nat+mangle)
- `ansible/roles/xray/tasks/main.yml` (TPROXY: geosite, capabilities, copy config)
- `ansible/roles/xray/templates/config.json.j2` (удалить — заменяется copy из secrets/)
- `ansible/roles/common/templates/90-route-override.yaml.j2` (новый — netplan)
- `ansible/playbooks/team-vms.yml` (pre_tasks для route override)

### Секреты (ручное управление):
- `secrets/xray-config.json` — пользователь создаёт/редактирует вручную, Ansible копирует на edge

### Не трогаем (сейчас):
- `ansible/roles/traefik/` — шаблоны ещё TODO-заглушки
- `modules/team-credentials/` — не зависит от сети
- `modules/*/versions.tf` — provider constraints не меняются
- `local_file.ansible_inventory` — пересоздастся Terraform автоматически

### Очистка (после успешного deploy):
- `environments/dev/variables.tf` — удалить неиспользуемые VLESS переменные (`vless_server`, `vless_uuid`, etc.) т.к. Xray конфиг теперь ручной секрет
- `environments/dev/terraform.tfvars.example` — убрать секцию Xray/VLESS Configuration

## Верификация

### Сеть + NAT
1. `terraform validate` + `terraform plan` — проверить: 1 subnet, 1 SG, edge VM (1 interface, no SG), team VMs
2. `ssh jump@176.109.104.2` — SSH на edge
3. На edge: `curl ifconfig.me` → 176.109.104.2
4. На edge: `iptables -L -n` → INPUT=DROP default, FORWARD=DROP default
5. На edge: `iptables -t nat -L -n` → MASQUERADE + hairpin
6. `ssh -o ProxyJump=jump@176.109.104.2 dashboard@10.0.1.100` — SSH на dashboard
7. На dashboard: `ip route` → default via 10.0.1.10
8. На dashboard: `ping 8.8.8.8` → работает (через edge NAT)
9. На dashboard: `curl ifconfig.me` → 176.109.104.2 (MASQUERADE через edge)
10. На dashboard: `nslookup google.com` → DNS работает

### TPROXY (Xray)
11. На edge: `systemctl status xray` → active (running)
12. На edge: `iptables -t mangle -L -n` → TPROXY правила (port 12345, 5353)
13. На edge: `ip rule list` → fwmark 1 → table 100
14. На edge: `cat /var/log/xray/access.log` → логи подключений
15. На dashboard: `curl -I https://api.openai.com` → 200 (через Xray TPROXY → VLESS)
16. На dashboard: `curl -I https://youtube.com` → 200 (через VLESS)
17. На dashboard: `curl -I https://ya.ru` → 200 (direct, без VLESS)

## Откат (rollback)

Если deploy на шаге 18 не проходит:
1. `terraform destroy` (удалит новые ресурсы)
2. В Cloud.ru console проверить что FIP (176.109.104.2) сохранён
3. Восстановить старый код из git (`git checkout main -- modules/ environments/`)
4. Пересоздать инфраструктуру с двумя подсетями

Если проблема только в Ansible (VM создались, но конфигурация сломана):
1. SSH на edge через серийную консоль (vm_password)
2. `iptables -F && iptables -P INPUT ACCEPT` — сбросить firewall
3. Исправить Ansible и перезапустить playbook

## Изменения от ревью (2026-03-17)

**Раунд 1:**
- **Добавлен** loopback в iptables INPUT — без него ломаются localhost-сервисы
- **Добавлены** явные FORWARD-правила — гарантия работы NAT
- **Убран** шаг xray iptables — правил ещё нет в кодовой базе
- **Добавлен** DNS (8.8.8.8, 8.8.4.4) в netplan team VMs
- **Route change** реализован как `pre_tasks` в team-vms.yml вместо отдельной роли

**Раунд 2 (code review):**
- **Добавлена** предварительная верификация FIP + `interface_security_enabled=false` и fallback-план
- **Добавлены** все обязательные атрибуты в team SG (`name`, `description`, `availability_zone`, `ether_type`)
- **Убрано** дублирующее ICMP правило — уже покрыто `ip_protocol = "any"` от subnet_cidr
- **Переписан** iptables на template + `iptables-restore` — идемпотентность, атомарность, persist
- **Default policy** FORWARD=DROP (было ACCEPT) — defense in depth
- **Netplan** через template module вместо inline copy — консистентность с проектными паттернами
- **Добавлены** в файл-лист: `nat/defaults/main.yml`, `nat/handlers/main.yml`, `nat/templates/iptables.rules.j2`, `common/templates/90-route-override.yaml.j2`
- **Уточнено**: inventory template оставить `module.edge.private_ip` (output уже вернёт новый IP)
- **Добавлен** раздел отката (rollback)

**Раунд 3 (TPROXY):**
- **Добавлен** Xray TPROXY: dokodemo-door inbound, `secrets/xray-config.json` как ручной секрет
- **Добавлен** mangle table в `iptables.rules.j2` (условный, `xray_tproxy_enabled`)
- **Добавлен** ip rule/route для TPROXY policy routing + rc.local persistence
- **Добавлены** geosite.dat/geoip.dat, CAP_NET_ADMIN, log directory
- **Добавлена** верификация TPROXY (systemctl, mangle rules, curl AI APIs)

**Раунд 4 (финальное ревью):**
- **Добавлен** RETURN для intra-subnet трафика в mangle — без этого team↔team TCP шёл бы через Xray
- **Заменён** `community.general.capabilities` на `command: setcap` — нет зависимости от collection
- **Добавлен** `systemd: name=rc-local enabled=true` — rc.local не запускается по умолчанию на Ubuntu 22.04
- **Добавлен** `xray_tproxy_port` в `group_vars/edge.yml` — nat role template не видит defaults xray role
- **Исправлен** текст "рендерится Terraform" → "ручной секрет"
- **Исправлена** нумерация шагов (Ansible 9-13, Фаза 3: 14-18)
- **Добавлена** секция очистки VLESS переменных из Terraform после deploy
