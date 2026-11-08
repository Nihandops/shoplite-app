data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------- security group (no ingress from the internet at all) ----------------
resource "aws_security_group" "nodes" {
  name        = "${var.name}-k8s-nodes"
  description = "Kubernetes nodes: intra-cluster only; ALB->NodePort rule is added by the alb module"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-k8s-nodes" }
}

resource "aws_vpc_security_group_ingress_rule" "intra_cluster" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
  description                  = "node-to-node: API server 6443, kubelet 10250, etcd, Calico VXLAN 4789/udp, pod traffic"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "outbound via NAT (packages, ECR, SSM endpoints)"
}

# ---------------- IAM: SSM Session Manager + ECR pull ----------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-k8s-node"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_ro" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-k8s-node"
  role = aws_iam_role.node.name
}

resource "aws_key_pair" "admin" {
  key_name   = "${var.name}-admin"
  public_key = var.ssh_public_key
}

locals {
  nodes = merge(
    { "control-plane" = { type = var.control_plane_instance_type, subnet = 0, role = "control-plane" } },
    { for i in range(var.worker_count) : "worker-${i + 1}" => {
      type = var.worker_instance_type, subnet = i % 2, role = "worker" } }
  )
}

resource "aws_instance" "node" {
  for_each               = local.nodes
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = each.value.type
  subnet_id              = var.private_subnet_ids[each.value.subnet]
  vpc_security_group_ids = [aws_security_group.nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name
  key_name               = aws_key_pair.admin.key_name

  associate_public_ip_address = false

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  user_data = <<-EOT
    #!/bin/bash
    hostnamectl set-hostname ${var.name}-${each.key}
  EOT

  tags = {
    Name       = "${var.name}-${each.key}"
    k8s-role   = each.value.role
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
