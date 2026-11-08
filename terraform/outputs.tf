output "app_url" { value = module.alb.url }
output "alb_dns_name" { value = module.alb.dns_name }
output "ecr_repositories" { value = module.ecr.repository_urls }
output "ecr_registry" { value = module.ecr.registry }
output "control_plane_instance_id" { value = module.compute.control_plane.id }
output "workers" { value = module.compute.workers }
output "vpc_id" { value = module.network.vpc_id }
