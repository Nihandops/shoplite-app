variable "name" { type = string }
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "one_nat_per_az" {
  type    = bool
  default = false
}
