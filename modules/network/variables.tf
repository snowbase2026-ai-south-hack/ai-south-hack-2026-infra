variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone_id" {
  description = "Cloud.ru Evolution availability zone ID"
  type        = string
}

variable "project_name" {
  description = "Project name used as prefix for resource names"
  type        = string
  default     = "aicamp"
}
