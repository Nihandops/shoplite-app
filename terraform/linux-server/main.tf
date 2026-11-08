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
  default = "ap-southeast-1"
}
variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/shoplite.pub"
}
variable "my_ip_cidr" {
  type        = string
  description = "Your public IP in CIDR form, e.g. 203.0.113.7/32"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# This account has no default VPC, so the practice server gets its own tiny public VPC.
resource "aws_vpc" "q3" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "shoplite-linux-server" }
}

resource "aws_internet_gateway" "q3" {
  vpc_id = aws_vpc.q3.id
}

resource "aws_subnet" "q3" {
  vpc_id                  = aws_vpc.q3.id
  cidr_block              = "10.50.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "q3" {
  vpc_id = aws_vpc.q3.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.q3.id
  }
}

resource "aws_route_table_association" "q3" {
  subnet_id      = aws_subnet.q3.id
  route_table_id = aws_route_table.q3.id
}

resource "aws_key_pair" "this" {
  key_name   = "shoplite-linux-server"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_security_group" "server" {
  name   = "shoplite-linux-server"
  vpc_id = aws_vpc.q3.id

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
  subnet_id              = aws_subnet.q3.id
  vpc_security_group_ids = [aws_security_group.server.id]
  metadata_options { http_tokens = "required" }
  root_block_device {
    volume_size = 20
    encrypted   = true
  }
  user_data = <<-EOT
    #!/bin/bash
    apt-get update -y
    apt-get install -y make git acl ufw curl
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker ubuntu
  EOT
  tags = { Name = "shoplite-linux-server" }
}

output "public_ip" { value = aws_instance.server.public_ip }
output "ssh" { value = "ssh -i ~/.ssh/shoplite ubuntu@${aws_instance.server.public_ip}" }
