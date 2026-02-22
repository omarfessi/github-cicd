variable "project_id" {
  type        = string
  description = "GCP Project ID"
  default     = "tooling-2026"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "europe-west9"
}

variable "github_org" {
  type        = string
  description = "GitHub organization/username"
  default     = "omarfessi"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
  default     = "github-cicd"
}

variable "service_account_id" {
  type        = string
  description = "Service account ID"
  default     = "github-workflows-terraform"
}

variable "workload_identity_pool_id" {
  type        = string
  description = "Workload Identity Pool ID"
  default     = "gha-pool-terraform"
}

variable "workload_identity_provider_id" {
  type        = string
  description = "Workload Identity Provider ID"
  default     = "gha-provider-terraform"
}

#Make sur to generate github token and export it when terraform apply
variable "github_token" {
  type        = string
  description = "GitHub personal access token (optional, for setting GitHub variables)"
  sensitive   = true
  default     = ""
}
# In case need to activate apis
# variable "apis" {
#   type = list(string)
#   default = [
#   ]
# }