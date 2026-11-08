# Bastion host (Q4c allows "bastion host or SSM"; SSM sessions are blocked in the Poridhi lab account).
variable "use_bastion" {
  type    = bool
  default = false
}

variable "admin_cidr" {
  type        = string
  default     = "127.0.0.1/32"
  description = "Your public IP/32 allowed to SSH to the bastion"
}

data "aws_ami" "bastion" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "bastion" {
  count       = var.use_bastion ? 1 : 0
  name        = "${var.name}-bastion"
  description = "SSH bastion: port 22 from the admin IP only"
  vpc_id      = module.network.vpc_id
  tags        = { Name = "${var.name}-bastion" }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  count             = var.use_bastion ? 1 : 0
  security_group_id = aws_security_group.bastion[0].id
  cidr_ipv4         = var.admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH from admin IP"
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  count             = var.use_bastion ? 1 : 0
  security_group_id = aws_security_group.bastion[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "nodes_from_bastion" {
  count                        = var.use_bastion ? 1 : 0
  security_group_id            = module.compute.node_security_group_id
  referenced_security_group_id = aws_security_group.bastion[0].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  description                  = "SSH from bastion only"
}

resource "aws_vpc_security_group_ingress_rule" "api_from_bastion" {
  count                        = var.use_bastion ? 1 : 0
  security_group_id            = module.compute.node_security_group_id
  referenced_security_group_id = aws_security_group.bastion[0].id
  from_port                    = 6443
  to_port                      = 6443
  ip_protocol                  = "tcp"
  description                  = "kubectl via bastion tunnel"
}

resource "aws_instance" "bastion" {
  count                       = var.use_bastion ? 1 : 0
  ami                         = data.aws_ami.bastion.id
  instance_type               = "t3.micro"
  subnet_id                   = module.network.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion[0].id]
  key_name                    = "${var.name}-admin"
  associate_public_ip_address = true
  metadata_options { http_tokens = "required" }
  root_block_device {
    volume_size = 8
    encrypted   = true
  }
  tags       = { Name = "${var.name}-bastion" }
  depends_on = [module.compute]
}

output "bastion_public_ip" {
  value = var.use_bastion ? aws_instance.bastion[0].public_ip : ""
}
