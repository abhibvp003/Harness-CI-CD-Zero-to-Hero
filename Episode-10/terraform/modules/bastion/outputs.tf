output "public_ip" {
  value = aws_instance.bastion.public_ip
}

output "instance_id" {
  value = aws_instance.bastion.id
}

output "iam_role_arn" {
  value = aws_iam_role.bastion.arn
}
