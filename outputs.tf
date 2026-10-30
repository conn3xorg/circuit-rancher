output "url" {
  description = "Address of Rancher's UI and API."
  value       = "https://${var.hostname}"
}

output "rancher_version" {
  description = "Rancher chart version installed."
  value       = var.rancher_version
}
