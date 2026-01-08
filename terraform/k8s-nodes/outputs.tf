
output "node_public_ips" {
  value = [for i in aws_instance.node : i.public_ip]
}
