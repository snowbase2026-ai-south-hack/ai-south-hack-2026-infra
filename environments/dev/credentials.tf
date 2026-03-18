# =============================================================================
# Team Credentials Management
# =============================================================================
# Saves SSH keys to files and generates credentials documentation.
# Keys are generated in main.tf. Separated for independent updates.
# =============================================================================

module "team_credentials" {
  source = "../../modules/team-credentials"

  teams = {
    for team_id, team_config in var.teams :
    team_id => {
      user       = team_config.user
      private_ip = module.team_vm.team_ips[team_id]
    }
  }

  domain     = var.domain
  jump_user  = var.jump_user
  bastion_ip = module.edge.public_ip

  # Single key per team
  team_private_keys = { for k, v in tls_private_key.team_key : k => v.private_key_openssh }
  team_public_keys  = { for k, v in tls_private_key.team_key : k => v.public_key_openssh }

  depends_on = [module.edge, module.team_vm]
}
