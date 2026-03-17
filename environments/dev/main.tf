# =============================================================================
# AI Talent Camp Infrastructure - Development Environment
# Cloud.ru Evolution
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    cloudru = {
      source  = "cloud.ru/cloudru/cloud"
      version = ">= 1.6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}

# =============================================================================
# Provider Configuration
# =============================================================================

provider "cloudru" {
  project_id         = var.project_id
  auth_key_id        = var.auth_key_id
  auth_secret        = var.auth_secret
  iam_endpoint       = "iam.api.cloud.ru:443"
  evolution_endpoint = "https://compute.api.cloud.ru"
}

# =============================================================================
# Data Sources: Availability Zone, Flavors, Disk Types
# =============================================================================

data "cloudru_evolution_availability_zone" "azs" {
  filter {}
}

locals {
  az = [
    for s in data.cloudru_evolution_availability_zone.azs.resources : s if s.name == var.availability_zone_name
  ][0]
}

# Edge VM flavor (2 vCPU / 4 GB)
data "cloudru_evolution_flavor" "edge" {
  filter {
    cpu = var.edge_cores
    ram = var.edge_memory
  }
}

locals {
  edge_flavor = [
    for s in data.cloudru_evolution_flavor.edge.resources : s if can(regex("^gen-", s.name))
  ][0]
}

# Team VM flavor (4 vCPU / 8 GB)
data "cloudru_evolution_flavor" "team" {
  filter {
    cpu = var.team_cores
    ram = var.team_memory
  }
}

locals {
  team_flavor = [
    for s in data.cloudru_evolution_flavor.team.resources : s if can(regex("^gen-", s.name))
  ][0]
}

# Disk type (SSD)
data "cloudru_evolution_disk_type" "ssd" {
  filter {}
}

locals {
  ssd_disk_type = [
    for s in data.cloudru_evolution_disk_type.ssd.resources : s if s.name == "SSD"
  ][0]
}

# =============================================================================
# SSH Keys Generation for Teams
# =============================================================================

# Jump keys (for bastion access) - unique per team
resource "tls_private_key" "team_jump_key" {
  for_each  = var.teams
  algorithm = "ED25519"
}

# VM keys (for team VM access)
resource "tls_private_key" "team_vm_key" {
  for_each  = var.teams
  algorithm = "ED25519"
}

# GitHub deploy keys (for CI/CD)
resource "tls_private_key" "team_github_key" {
  for_each  = var.teams
  algorithm = "ED25519"
}

# =============================================================================
# Module: Network (single subnet)
# =============================================================================

module "network" {
  source = "../../modules/network"

  subnet_cidr          = var.subnet_cidr
  availability_zone_id = local.az.id
  project_name         = var.project_name
}

# =============================================================================
# Module: Security Groups
# =============================================================================

module "security" {
  source = "../../modules/security"

  name                 = var.project_name
  subnet_cidr          = var.subnet_cidr
  edge_private_ip      = cidrhost(var.subnet_cidr, 10)
  availability_zone_id = local.az.id
}

# =============================================================================
# Module: Edge VM (NAT Gateway + Jump Host)
# =============================================================================

module "edge" {
  source = "../../modules/edge"

  flavor_id              = local.edge_flavor.id
  disk_type_id           = local.ssd_disk_type.id
  disk_size              = var.edge_disk_size
  availability_zone_id   = local.az.id
  availability_zone_name = var.availability_zone_name
  subnet_name            = module.network.subnet_name
  ip_address             = cidrhost(var.subnet_cidr, 10)
  user_name              = var.jump_user
  public_key             = var.jump_public_key
  password               = var.vm_password

  depends_on = [module.network]
}

# =============================================================================
# Module: Team VMs
# =============================================================================

module "team_vm" {
  source = "../../modules/team_vm"

  teams                  = var.teams
  flavor_id              = local.team_flavor.id
  disk_type_id           = local.ssd_disk_type.id
  disk_size              = var.team_disk_size
  availability_zone_name = var.availability_zone_name
  subnet_name            = module.network.subnet_name
  security_group_id      = module.security.team_sg_id
  password               = var.vm_password
  team_public_keys = {
    for team_id, key in tls_private_key.team_vm_key : team_id => key.public_key_openssh
  }

  depends_on = [module.network, module.security]
}

# =============================================================================
# Ansible Inventory Generation
# =============================================================================

resource "local_file" "ansible_inventory" {
  count = length(var.teams) > 0 ? 1 : 0

  filename = "${path.module}/../../ansible/inventory/hosts.yml"
  content = templatefile("${path.module}/../../ansible/templates/inventory.yml.tpl", {
    edge_public_ip  = module.edge.public_ip
    edge_private_ip = module.edge.private_ip
    edge_user       = var.jump_user
    teams = {
      for id, team in var.teams : id => {
        user       = team.user
        private_ip = module.team_vm.team_ips[id]
      }
    }
  })

  depends_on = [module.edge, module.team_vm]
}
