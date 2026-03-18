output "subnet_id" {
  description = "ID of the subnet"
  value       = cloudru_evolution_subnet.main.id
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = cloudru_evolution_subnet.main.name
}

output "subnet_cidr" {
  description = "CIDR block of the subnet"
  value       = var.subnet_cidr
}
