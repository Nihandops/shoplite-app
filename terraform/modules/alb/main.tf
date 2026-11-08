resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public ALB: HTTP/HTTPS from the internet"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "to_nodes" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = var.node_security_group_id
  from_port                    = var.ingress_node_port
  to_port                      = var.ingress_node_port
  ip_protocol                  = "tcp"
  description                  = "ALB to ingress controller NodePort only"
}

# the ONLY way into the nodes from outside the cluster
resource "aws_vpc_security_group_ingress_rule" "nodes_from_alb" {
  security_group_id            = var.node_security_group_id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.ingress_node_port
  to_port                      = var.ingress_node_port
  ip_protocol                  = "tcp"
  description                  = "ingress controller NodePort from ALB"
}

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
  idle_timeout       = 60
}

resource "aws_lb_target_group" "ingress" {
  name        = "${var.name}-ingress"
  port        = var.ingress_node_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/"
    matcher             = "200-499" # healthy as long as the ingress controller answers
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group_attachment" "workers" {
  count            = length(var.target_instance_ids)
  target_group_arn = aws_lb_target_group.ingress.arn
  target_id        = var.target_instance_ids[count.index]
  port             = var.ingress_node_port
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = var.domain_name == "" ? "forward" : "redirect"
    target_group_arn = var.domain_name == "" ? aws_lb_target_group.ingress.arn : null

    dynamic "redirect" {
      for_each = var.domain_name == "" ? [] : [1]
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

# ---------------- optional: Route 53 + ACM + HTTPS when a domain is available ----------------
data "aws_route53_zone" "this" {
  count = var.domain_name == "" ? 0 : 1
  name  = var.hosted_zone_name
}

resource "aws_acm_certificate" "this" {
  count             = var.domain_name == "" ? 0 : 1
  domain_name       = var.domain_name
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "validation" {
  for_each = var.domain_name == "" ? {} : {
    for o in aws_acm_certificate.this[0].domain_validation_options : o.domain_name => o
  }
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  count                   = var.domain_name == "" ? 0 : 1
  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

resource "aws_lb_listener" "https" {
  count             = var.domain_name == "" ? 0 : 1
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.this[0].certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress.arn
  }
}

resource "aws_route53_record" "app" {
  count   = var.domain_name == "" ? 0 : 1
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
