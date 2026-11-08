variable "name" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "ssh_public_key" {
  type        = string
  description = "Public key used by Ansible (SSH tunnelled through SSM, port 22 is NOT open)"
}
variable "control_plane_instance_type" {
  type    = string
  default = "t3.medium"
}
variable "worker_instance_type" {
  type    = string
  default = "t3.large"
}
variable "worker_count" {
  type    = number
  default = 2
}
variable "root_volume_gb" {
  type    = number
  default = 30
}
