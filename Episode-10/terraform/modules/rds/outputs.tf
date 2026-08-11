output "endpoint" {
  value = aws_db_instance.main.endpoint
}

output "secret_name" {
  value = aws_secretsmanager_secret.db_credentials.name
}
