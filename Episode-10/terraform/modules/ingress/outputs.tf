output "acm_certificate_arn" {
  value = data.aws_acm_certificate.wildcard.arn
}
