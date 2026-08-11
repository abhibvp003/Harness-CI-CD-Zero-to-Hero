output "service_identifier" {
  value = harness_platform_service.online_boutique.identifier
}

output "production_env_identifier" {
  value = harness_platform_environment.production.identifier
}

output "prometheus_connector_id" {
  value = harness_platform_connector_prometheus.prometheus.identifier
}
