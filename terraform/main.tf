terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.8.0"
    }
    github = {
      source  = "integrations/github"
      version = "6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# GitHub provider (only if github_token is provided)
provider "github" {
  owner = var.github_org
  token = var.github_token
}

provider "random" {}

# ============================================================================
# Random Suffix for Workload Identity Resources
# ============================================================================
# GCP has a 30-day grace period for deleted resources.
# Using a random suffix ensures we can create a new pool/provider
# even if the previous one is still in the grace period.

resource "random_string" "wip_suffix" {
  length  = 4
  special = false
  upper   = false
}

# resource "google_project_service" "apis" {
#   for_each                   = toset(var.apis)
#   project                    = var.project_id
#   service                    = each.key
#   disable_dependent_services = true
# }

# ============================================================================
# Service Account
# ============================================================================

resource "google_service_account" "github_workflows" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "GitHub Actions Service Account"
  description  = "Service account for GitHub Actions CI/CD workflows"
}

# ============================================================================
# Workload Identity Pool
# ============================================================================

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.workload_identity_pool_id}-${random_string.wip_suffix.result}"
  display_name              = "GitHub Actions"
  description               = "Workload Identity Pool for GitHub Actions"
  disabled                  = false
}

# ============================================================================
# Workload Identity Provider (OIDC)
# ============================================================================

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.workload_identity_provider_id
  display_name                       = "GitHub Actions OIDC Provider"
  description                        = "OIDC provider for GitHub Actions authentication"
  disabled                           = false

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  # Security: Only accept tokens from your GitHub organization
  attribute_condition = "assertion.repository_owner == '${var.github_org}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ============================================================================
# IAM Policy Binding
# ============================================================================

resource "google_service_account_iam_binding" "github_workload_identity_user" {
  service_account_id = google_service_account.github_workflows.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_repo}"
  ]

  depends_on = [google_iam_workload_identity_pool_provider.github]
}

# ============================================================================
# GitHub Actions Variables (Optional)
# ============================================================================

# Only create if github_token is provided
resource "github_actions_variable" "service_account_email" {
  repository        = var.github_repo
  variable_name     = "SERVICE_ACCOUNT_EMAIL"
  value             = google_service_account.github_workflows.email
}

resource "github_actions_variable" "workload_identity_provider" {
  repository        = var.github_repo
  variable_name     = "WORKLOAD_IDENTITY_PROVIDER"
  value             = google_iam_workload_identity_pool_provider.github.name
}