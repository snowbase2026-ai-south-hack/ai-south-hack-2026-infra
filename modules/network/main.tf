resource "cloudru_evolution_subnet" "main" {
  name            = "${var.project_name}-subnet"
  subnet_address  = var.subnet_cidr
  default_gateway = cidrhost(var.subnet_cidr, 1)
  routed_network  = true

  availability_zone {
    id = var.availability_zone_id
  }
}
