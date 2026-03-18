# =============================================================================
# AI South Hack SSH Config for ${team_id}
# =============================================================================
# Usage:
#   1. Run setup.sh (Mac/Linux) or setup.ps1 (Windows)
#   2. ssh ${team_id}
# =============================================================================

Host bastion
  HostName bastion.${domain}
  User ${jump_user}
  IdentityFile ~/.ssh/ai-south-hack/${team_id}-key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host ${team_id}
  HostName ${team_private_ip}
  User ${team_user}
  ProxyJump bastion
  IdentityFile ~/.ssh/ai-south-hack/${team_id}-key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
