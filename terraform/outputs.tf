output "service_account_email" {
  description = "Service account email address"
  value       = google_service_account.github_workflows.email
}

output "service_account_id" {
  description = "Service account ID"
  value       = google_service_account.github_workflows.account_id
}

output "workload_identity_pool_id" {
  description = "Full Workload Identity Pool resource ID"
  value       = google_iam_workload_identity_pool.github.name
}

output "workload_identity_provider_id" {
  description = "Full Workload Identity Provider resource ID"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_repository" {
  description = "GitHub repository authorized to use this setup"
  value       = "${var.github_org}/${var.github_repo}"
}

output "github_organization" {
  description = "GitHub organization authorized at the pool level"
  value       = var.github_org
}