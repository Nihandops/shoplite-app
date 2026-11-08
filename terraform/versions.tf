terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws   = { source = "hashicorp/aws", version = "~> 5.80" }
    local = { source = "hashicorp/local", version = "~> 2.5" }
  }

  # Remote state in S3 with S3-native locking (use_lockfile, Terraform >= 1.10).
  # bucket is passed at init time:  terraform init -backend-config="bucket=shoplite-tfstate-<ACCOUNT_ID>"
  backend "s3" {
    key          = "shoplite/main.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      project    = "shoplite"
      managed-by = "terraform"
    }
  }
}
