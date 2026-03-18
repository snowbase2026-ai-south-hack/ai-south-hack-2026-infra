# =============================================================================
# Network Outputs
# =============================================================================

output "subnet_id" {
  description = "ID of the subnet"
  value       = module.network.subnet_id
}

# =============================================================================
# Edge VM Outputs
# =============================================================================

output "edge_public_ip" {
  description = "Public (floating) IP address of the edge/NAT VM"
  value       = module.edge.public_ip
}

output "edge_private_ip" {
  description = "Private IP address of the edge/NAT VM"
  value       = module.edge.private_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion (admin)"
  value       = "ssh ${var.jump_user}@${module.edge.public_ip}"
}

# =============================================================================
# Team VM Outputs
# =============================================================================

output "team_vms" {
  description = "Map of team VM names to their private IPs"
  value       = length(var.teams) > 0 ? module.team_vm.team_ips : {}
}

output "team_ssh_commands" {
  description = "SSH commands to connect to team VMs (via bastion)"
  value = {
    for team_id, team_config in var.teams :
    team_id => "ssh -o ProxyJump=${var.jump_user}@${module.edge.public_ip} ${team_config.user}@${module.team_vm.team_ips[team_id]}"
  }
}

# =============================================================================
# DNS Configuration
# =============================================================================

output "dns_records" {
  description = "DNS records to configure"
  value = {
    wildcard = "*.${var.domain} -> ${module.edge.public_ip}"
    bastion  = "bastion.${var.domain} -> ${module.edge.public_ip}"
  }
}

# =============================================================================
# Team Credentials Location
# =============================================================================

output "team_credentials_folders" {
  description = "Location of generated credentials for each team"
  value = {
    for team_id, team_config in var.teams :
    team_id => "secrets/team-${team_id}/"
  }
}

output "credentials_summary" {
  description = "Path to JSON file with all team credentials"
  value       = length(var.teams) > 0 ? "secrets/teams-credentials.json" : null
}
