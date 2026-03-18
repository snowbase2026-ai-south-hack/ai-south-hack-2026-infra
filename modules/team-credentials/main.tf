# =============================================================================
# Team Credentials Module
# =============================================================================
# This module handles saving SSH keys to files and generating credentials
# documentation, separate from key generation and infrastructure provisioning.
# =============================================================================

# =============================================================================
# Team Directory Structure
# =============================================================================

resource "local_file" "team_dir_marker" {
  for_each = var.teams

  filename = "${path.module}/${var.secrets_path}/team-${each.key}/.gitkeep"
  content  = ""
}

# =============================================================================
# Keys
# =============================================================================

# Rename from team_vm_private_key / team_vm_public_key — preserves state, no file churn.
moved {
  from = local_file.team_vm_private_key
  to   = local_file.team_private_key
}

moved {
  from = local_file.team_vm_public_key
  to   = local_file.team_public_key
}

resource "local_file" "team_private_key" {
  for_each = var.teams

  filename        = "${path.module}/${var.secrets_path}/team-${each.key}/${each.key}-key"
  content         = var.team_private_keys[each.key]
  file_permission = "0600"
}

resource "local_file" "team_public_key" {
  for_each = var.teams

  filename = "${path.module}/${var.secrets_path}/team-${each.key}/${each.key}-key.pub"
  content  = var.team_public_keys[each.key]
}

# =============================================================================
# SSH Config Files
# =============================================================================

# Track team IP changes with terraform_data for controlled updates
resource "terraform_data" "team_ip_tracker" {
  for_each = var.teams

  input = {
    team_id    = each.key
    user       = each.value.user
    private_ip = each.value.private_ip
  }
}

resource "local_file" "team_ssh_config" {
  for_each = var.teams

  filename = "${path.module}/${var.secrets_path}/team-${each.key}/ssh-config"
  content = templatefile("${path.module}/../../templates/team/ssh-config.tpl", {
    team_id         = each.key
    team_user       = each.value.user
    domain          = var.domain
    jump_user       = var.jump_user
    team_private_ip = terraform_data.team_ip_tracker[each.key].output.private_ip
  })

  depends_on = [terraform_data.team_ip_tracker]
}

# =============================================================================
# Participant Setup Scripts
# =============================================================================

resource "local_file" "team_setup_sh" {
  for_each = var.teams

  filename = "${path.module}/${var.secrets_path}/team-${each.key}/setup.sh"
  content = templatefile("${path.module}/../../templates/team/setup.sh.tpl", {
    team_id   = each.key
    team_user = each.value.user
  })
  file_permission = "0755"
}

resource "local_file" "team_setup_bat" {
  for_each = var.teams

  filename        = "${path.module}/${var.secrets_path}/team-${each.key}/setup.bat"
  file_permission = "0644"
  # Plain ASCII — no BOM, no Cyrillic; standalone alternative to setup.ps1
  content = templatefile("${path.module}/../../templates/team/setup.bat.tpl", {
    team_id = each.key
  })
}

resource "local_file" "team_setup_ps1" {
  for_each = var.teams

  filename        = "${path.module}/${var.secrets_path}/team-${each.key}/setup.ps1"
  file_permission = "0644"
  # \uFEFF = UTF-8 BOM — required for PowerShell 5.x on Windows to read UTF-8 correctly
  content = "\uFEFF${templatefile("${path.module}/../../templates/team/setup.ps1.tpl", {
    team_id   = each.key
    team_user = each.value.user
  })}"
}

resource "local_file" "team_readme" {
  for_each = var.teams

  filename        = "${path.module}/${var.secrets_path}/team-${each.key}/README.md"
  file_permission = "0644"
  content = templatefile("${path.module}/../../templates/team/README.md.tpl", {
    team_id   = each.key
    team_user = each.value.user
    domain    = var.domain
  })
}

# =============================================================================
# Teams Credentials Summary JSON
# =============================================================================

resource "local_file" "teams_credentials_json" {
  filename = "${path.module}/${var.secrets_path}/teams-credentials.json"
  content = jsonencode({
    bastion = {
      host   = var.bastion_ip
      user   = var.jump_user
      domain = "bastion.${var.domain}"
    }
    teams = {
      for team_id, team_config in var.teams :
      team_id => {
        user        = team_config.user
        private_ip  = team_config.private_ip
        domain      = "${team_config.user}.${var.domain}"
        ssh_command = "ssh ${team_id}"
        folder      = "secrets/team-${team_id}/"
        files = {
          key        = "${team_id}-key"
          ssh_config = "ssh-config"
          setup_sh   = "setup.sh"
          setup_bat  = "setup.bat"
          setup_ps1  = "setup.ps1"
          readme     = "README.md"
        }
      }
    }
    traefik = {
      auto_config   = "secrets/traefik-dynamic-auto.yml"
      custom_config = "secrets/traefik-dynamic-custom.yml"
      note          = "auto_config is regenerated by Terraform, custom_config is for manual additions"
    }
  })
}
