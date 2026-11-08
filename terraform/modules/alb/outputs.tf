output "dns_name" { value = aws_lb.this.dns_name }
output "url" { value = var.domain_name == "" ? "http://${aws_lb.this.dns_name}" : "https://${var.domain_name}" }
output "security_group_id" { value = aws_security_group.alb.id }
