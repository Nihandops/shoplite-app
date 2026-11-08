variable "region" {
  type    = string
  default = "ap-southeast-1"
}
variable "name" {
  type    = string
  default = "shoplite"
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/shoplite.pub"
}
variable "control_plane_instance_type" {
  type    = string
  default = "t3.medium"
}
variable "worker_instance_type" {
  type    = string
  default = "t3.large"
}
variable "domain_name" {
  type    = string
  default = ""
}
variable "hosted_zone_name" {
  type    = string
  default = ""
}
