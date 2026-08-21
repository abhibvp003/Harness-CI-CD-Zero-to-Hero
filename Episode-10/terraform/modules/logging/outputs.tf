output "namespace" {
  value = "logging"
}

output "efk_password" {
  value     = random_password.efk.result
  sensitive = true
}
