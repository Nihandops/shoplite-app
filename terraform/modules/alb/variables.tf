variable "name" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "node_security_group_id" { type = string }
variable "target_instance_ids" { type = list(string) }
variable "ingress_node_port" {
  type    = number
  default = 30080
}
variable "domain_name" {
  type        = string
  default     = ""
  description = "e.g. shop.example.com — leave empty to use the ALB DNS name over HTTP"
}
variable "hosted_zone_name" {
  type    = string
  default = ""
}
