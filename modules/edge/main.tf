# =============================================================================
# Floating IP for Edge VM
# =============================================================================

resource "cloudru_evolution_fip" "edge" {
  name = "south-edge-fip"

  availability_zone {
    id = var.availability_zone_id
  }
}

# =============================================================================
# Edge VM Instance (single interface with FIP)
# =============================================================================

resource "cloudru_evolution_compute" "edge" {
  name      = "south-edge"
  flavor_id = var.flavor_id

  availability_zone {
    name = var.availability_zone_name
  }

  image {
    name       = "ubuntu-22.04"
    host_name  = "south-edge"
    user_name  = var.user_name
    public_key = var.public_key
    password   = var.password
  }

  boot_disk {
    name = "south-edge-boot"
    size = var.disk_size

    disk_type {
      id = var.disk_type_id
    }
  }

  network_interfaces {
    subnet { name = var.subnet_name }
    ip_address                 = var.ip_address
    interface_security_enabled = false
    fip { id = cloudru_evolution_fip.edge.id }
  }
}
