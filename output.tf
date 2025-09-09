
output "devlake_public_ip" {
  value = aws_instance.devlake_ec2.public_ip
}

output "devlake_alb_dns" {
  value = aws_lb.devlake_alb.dns_name
}
