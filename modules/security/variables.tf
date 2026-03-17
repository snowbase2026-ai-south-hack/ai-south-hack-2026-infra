variable "name" {
  description = "Base name for security groups"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR block of the subnet"
  type        = string
}

variable "edge_private_ip" {
  description = "Private IP address of the edge VM"
  type        = string
}

variable "availability_zone_id" {
  description = "Availability zone ID for security groups"
  type        = string
}
