module "network" {
  source         = "./modules/network"
  name           = var.name
  vpc_cidr       = var.vpc_cidr
  one_nat_per_az = false
}

module "compute" {
  source                      = "./modules/compute"
  name                        = var.name
  vpc_id                      = module.network.vpc_id
  private_subnet_ids          = module.network.private_subnet_ids
  ssh_public_key              = file(pathexpand(var.ssh_public_key_path))
  control_plane_instance_type = var.control_plane_instance_type
  worker_instance_type        = var.worker_instance_type
  worker_count                = 2
}

module "alb" {
  source                 = "./modules/alb"
  name                   = var.name
  vpc_id                 = module.network.vpc_id
  public_subnet_ids      = module.network.public_subnet_ids
  node_security_group_id = module.compute.node_security_group_id
  target_instance_ids    = module.compute.worker_instance_ids
  ingress_node_port      = 30080
  domain_name            = var.domain_name
  hosted_zone_name       = var.hosted_zone_name
}

module "ecr" {
  source       = "./modules/ecr"
  prefix       = "shoplite"
  repositories = ["web", "catalog-api", "order-worker"]
}

# Ansible inventory generated from Terraform outputs (SSH is tunnelled through SSM).
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/hosts.ini.tftpl", {
    region        = var.region
    control_plane = module.compute.control_plane
    workers       = module.compute.workers
    vpc_cidr      = module.network.vpc_cidr
    ssh_key       = replace(pathexpand(var.ssh_public_key_path), ".pub", "")
  })
}
