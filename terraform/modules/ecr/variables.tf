variable "prefix" {
  type    = string
  default = "shoplite"
}
variable "repositories" {
  type    = list(string)
  default = ["web", "catalog-api", "order-worker"]
}
