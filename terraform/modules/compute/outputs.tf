output "node_security_group_id" { value = aws_security_group.nodes.id }

output "control_plane" {
  value = { id = aws_instance.node["control-plane"].id, private_ip = aws_instance.node["control-plane"].private_ip }
}

output "workers" {
  value = { for k, v in aws_instance.node : k => { id = v.id, private_ip = v.private_ip } if k != "control-plane" }
}

output "worker_instance_ids" {
  value = [for k, v in aws_instance.node : v.id if k != "control-plane"]
}
