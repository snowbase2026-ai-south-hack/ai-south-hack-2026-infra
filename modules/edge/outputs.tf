output "instance_id" {
  description = "ID of the edge compute instance"
  value       = cloudru_evolution_compute.edge.id
}

output "public_ip" {
  description = "Floating IP address of the edge VM"
  value       = cloudru_evolution_fip.edge.ip_address
}

output "private_ip" {
  description = "Static private IP on the network interface"
  value       = var.ip_address
}

output "fip_id" {
  description = "ID of the floating IP resource"
  value       = cloudru_evolution_fip.edge.id
}
