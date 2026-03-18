variable "flavor_id" {
  description = "Compute flavor ID (looked up via data source in environment)"
  type        = string
}

variable "disk_type_id" {
  description = "Boot disk type ID (looked up via data source in environment)"
  type        = string
}

variable "disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 20
}

variable "availability_zone_id" {
  description = "Availability zone ID for the floating IP"
  type        = string
}

variable "availability_zone_name" {
  description = "Availability zone name for the compute instance"
  type        = string
  default     = "ru.AZ-1"
}

variable "subnet_name" {
  description = "Name of the subnet for the network interface"
  type        = string
}

variable "user_name" {
  description = "Username for SSH access on the edge VM"
  type        = string
  default     = "jump"
}

variable "public_key" {
  description = "SSH public key for admin access"
  type        = string
}

variable "password" {
  description = "Password for serial console access"
  type        = string
  sensitive   = true
  default     = ""
}

variable "security_group_id" {
  description = "ID of the security group for the edge VM interface"
  type        = string
}

variable "ip_address" {
  description = "Static IP address for the edge VM"
  type        = string
  default     = "10.0.1.10"
}
