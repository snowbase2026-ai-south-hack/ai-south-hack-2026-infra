# =============================================================================
# AI South Hack SSH Config for ${team_user}
# =============================================================================
# Usage:
#   1. Copy this folder to ~/.ssh/ai-south-hack/
#   2. chmod 600 ~/.ssh/ai-south-hack/*-key
#   3. ssh -F ~/.ssh/ai-south-hack/ssh-config ${team_user}
# =============================================================================

Host bastion
  HostName bastion.${domain}
  User ${jump_user}
  IdentityFile ~/.ssh/ai-south-hack/${team_user}-key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host ${team_user}
  HostName ${team_private_ip}
  User ${team_user}
  ProxyJump bastion
  IdentityFile ~/.ssh/ai-south-hack/${team_user}-key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
