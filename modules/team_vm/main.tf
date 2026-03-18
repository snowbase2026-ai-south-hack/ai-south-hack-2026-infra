# =============================================================================
# Team VM Instances (Cloud.ru Evolution)
# =============================================================================
# Ansible handles Docker install, routes, and services post-provisioning.
# =============================================================================

locals {
  team_ips = { for id, team in var.teams : id => team.ip }
}

resource "cloudru_evolution_compute" "team" {
  for_each = var.teams

  name      = "south-${each.key}"
  flavor_id = var.flavor_id

  availability_zone {
    name = var.availability_zone_name
  }

  image {
    name       = "ubuntu-22.04"
    host_name  = "south-${each.key}"
    user_name  = each.value.user
    public_key = var.team_public_keys[each.key]
    password   = var.password
  }

  boot_disk {
    name = "south-${each.key}-boot"
    size = var.disk_size
    disk_type {
      id = var.disk_type_id
    }
  }

  network_interfaces {
    subnet {
      name = var.subnet_name
    }
    security_groups {
      id = var.security_group_id
    }
    ip_address = local.team_ips[each.key]
  }

  lifecycle {
    ignore_changes = [network_interfaces]
  }
}
