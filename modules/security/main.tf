# Placeholder SG for edge — not enforced (interface_security_enabled=false),
# but Cloud.ru requires at least one SG assigned to an interface
resource "cloudru_evolution_security_group" "edge" {
  name        = "${var.name}-edge-sg"
  description = "Permissive SG for edge VM (firewall via iptables)"

  availability_zone {
    id = var.availability_zone_id
  }

  rules {
    direction        = "ingress"
    ether_type       = "IPv4"
    ip_protocol      = "any"
    port_range       = "any"
    remote_ip_prefix = "0.0.0.0/0"
    description      = "Allow all inbound (iptables handles filtering)"
  }

  rules {
    direction        = "egress"
    ether_type       = "IPv4"
    ip_protocol      = "any"
    port_range       = "any"
    remote_ip_prefix = "0.0.0.0/0"
    description      = "Allow all outbound"
  }
}

resource "cloudru_evolution_security_group" "team" {
  name        = "${var.name}-team-sg"
  description = "Security group for team VMs"

  availability_zone {
    id = var.availability_zone_id
  }

  # SSH — only from edge
  rules {
    direction        = "ingress"
    ether_type       = "IPv4"
    ip_protocol      = "tcp"
    port_range       = "22:22"
    remote_ip_prefix = "${var.edge_private_ip}/32"
    description      = "SSH from edge"
  }

  # HTTP — only from edge (Traefik proxy)
  rules {
    direction        = "ingress"
    ether_type       = "IPv4"
    ip_protocol      = "tcp"
    port_range       = "80:80"
    remote_ip_prefix = "${var.edge_private_ip}/32"
    description      = "HTTP from edge"
  }

  # HTTPS — only from edge (Traefik proxy)
  rules {
    direction        = "ingress"
    ether_type       = "IPv4"
    ip_protocol      = "tcp"
    port_range       = "443:443"
    remote_ip_prefix = "${var.edge_private_ip}/32"
    description      = "HTTPS from edge"
  }

  # Inter-team: all protocols within subnet (including ICMP)
  rules {
    direction        = "ingress"
    ether_type       = "IPv4"
    ip_protocol      = "any"
    port_range       = "any"
    remote_ip_prefix = var.subnet_cidr
    description      = "All traffic within subnet"
  }

  # Egress — unrestricted
  rules {
    direction        = "egress"
    ether_type       = "IPv4"
    ip_protocol      = "any"
    port_range       = "any"
    remote_ip_prefix = "0.0.0.0/0"
    description      = "Allow all outbound traffic"
  }
}
