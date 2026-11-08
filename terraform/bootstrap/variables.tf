variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "budget_email" {
  type        = string
  description = "Email that receives AWS Budget alerts"
}

variable "github_owner" {
  type        = string
  description = "GitHub user or org that owns the shoplite-app repo"
}
