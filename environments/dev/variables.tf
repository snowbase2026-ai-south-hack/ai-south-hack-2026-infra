# =============================================================================
# Cloud.ru Evolution Configuration
# =============================================================================

variable "project_id" {
  description = "Cloud.ru Evolution project ID"
  type        = string
}

variable "auth_key_id" {
  description = "Cloud.ru service account API key ID"
  type        = string
  sensitive   = true
}

variable "auth_secret" {
  description = "Cloud.ru service account API secret"
  type        = string
  sensitive   = true
}

variable "availability_zone_name" {
  description = "Cloud.ru Evolution availability zone name"
  type        = string
  default     = "ru.AZ-1"
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# =============================================================================
# Project Configuration
# =============================================================================

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "aicamp"
}

variable "domain" {
  description = "Base domain for the camp"
  type        = string
  default     = "south.aitalenthub.ru"
}

# =============================================================================
# Edge VM Configuration
# =============================================================================

variable "edge_cores" {
  description = "Number of CPU cores for edge VM"
  type        = number
  default     = 2
}

variable "edge_memory" {
  description = "Memory in GB for edge VM"
  type        = number
  default     = 4
}

variable "edge_disk_size" {
  description = "Boot disk size in GB for edge VM"
  type        = number
  default     = 20
}

variable "jump_user" {
  description = "Username for jump host access"
  type        = string
  default     = "jump"
}

variable "jump_public_key" {
  description = "SSH public key for jump host user"
  type        = string
}

variable "vm_password" {
  description = "Password for VM serial console access"
  type        = string
  sensitive   = true
  default     = ""
}

# =============================================================================
# Team VM Configuration
# =============================================================================

variable "team_cores" {
  description = "Number of CPU cores for team VMs"
  type        = number
  default     = 4
}

variable "team_memory" {
  description = "Memory in GB for team VMs"
  type        = number
  default     = 8
}

variable "team_disk_size" {
  description = "Boot disk size in GB for team VMs"
  type        = number
  default     = 65
}

variable "teams" {
  description = "Map of teams with their configuration"
  type = map(object({
    user        = string
    public_keys = list(string)
    ip          = string
  }))
  default = {}
}

