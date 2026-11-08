# Q3 practice server: one public Ubuntu 22.04 EC2 that runs the Docker Compose stack.
# The security group deliberately ALSO opens 8000 and 5432 so that the "blocked port"
# demo proves UFW (not AWS) is doing the blocking. Destroy after taking screenshots.
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.80" }
  }
}

provider "aws" {
  region = var.region
  default_tags { tags = { project = "shoplite", managed-by = "terraform", stack = "linux-server" } }
}

variable "region" {
  type    = string
  default = "ap-south-1"
}
variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/shoplite.pub"
}
variable "my_ip_cidr" {
  type        = string
  description = "Your public IP in CIDR form, e.g. 203.0.113.7/32 (curl -s https://checkip.amazonaws.com)"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_key_pair" "this" {
  key_name   = "shoplite-linux-server"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_security_group" "server" {
  name   = "shoplite-linux-server"
  vpc_id = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = [22, 80, 443, 8000, 5432]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [ingress.value == 22 ? var.my_ip_cidr : "0.0.0.0/0"]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [aws_security_group.server.id]
  metadata_options { http_tokens = "required" }
  root_block_device {
    volume_size = 20
    encrypted   = true
  }
  user_data = <<-EOT
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io docker-compose-v2 make git acl ufw
    usermod -aG docker ubuntu
  EOT
  tags = { Name = "shoplite-linux-server" }
}

output "public_ip" { value = aws_instance.server.public_ip }
output "ssh" { value = "ssh -i ~/.ssh/shoplite ubuntu@${aws_instance.server.public_ip}" }
