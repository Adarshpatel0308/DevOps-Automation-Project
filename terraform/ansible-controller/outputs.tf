
output "controller_public_ip" {
  value = aws_instance.controller.public_ip
}

output "controller_private_ip" {
  value = aws_instance.controller.private_ip
}
