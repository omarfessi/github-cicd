# GitHub to Google Cloud Authentication via Workload Identity Federation

A comprehensive guide, inspired from [Google GitHub Actions Auth Action](https://github.com/google-github-actions/auth), for setting up keyless authentication between GitHub Actions and Google Cloud Platform using Workload Identity Federation.
In this guide I choose to authenticate Github Actions Workflow to GCP using Workload Identity Federation through a service account, Other methods are also provided in that Github repo.

## Overview

Workload Identity Federation allows GitHub Actions to authenticate to GCP without storing long-lived service account keys. Instead, GitHub generates a temporary OIDC token that GCP exchanges for short-lived credentials.

**Benefits:**
- No static credentials in GitHub secrets
- Automatic credential rotation (1 hour by default)
- Fine-grained access control per repository
- Audit trail of which repo performed what action

---

## Prerequisites

- `gcloud` CLI installed and authenticated
- Terraform installed
- GCP project
- GitHub repository where workflows will run
- Owner/admin access to both GCP project and GitHub repo

---

## Quick Start with Terraform (Recommended) ⚡

Instead of manually running `gcloud` commands like in [Google GitHub Actions Auth Action](https://github.com/google-github-actions/auth), I use Terraform to set up everything automatically, please refer to Manual Setup (Using gcloud commands) section if Terraform is not an option for your setup.

### Step 1: Create a Fine-Grained GitHub Personal Access Token

This token allows Terraform to automatically create GitHub repository variables.
Follow steps in this [link](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token:~:text=credentials%20secure.-,Creating%20a%20fine%2Dgrained%20personal%20access%20token,-Note) to configure a token

**Configure the token:**
- **Token name:** `terraform-wif` (or any name)
- **Expiration:** 90 days
- **Repository access:** Select **"Only select repositories"** → Choose your `github-cicd` repo
- **Permissions:** Select **"Variables"** and set to **"Read and write"**

⚠️ **Important:** Save it somewhere safe - you can't view it again!

### Step 2: Set Environment Variable

```bash
# Export the token as TF_VAR_github_token
export TF_VAR_github_token="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```
Or just issue this command: source .env.example after copying your token in the file and do not commit it.

### Step 3: Initialize and Apply Terraform

```bash
# Initialize Terraform (download providers)
terraform init

# Preview what will be created
terraform plan

# Create all resources
terraform apply
```

**What gets created:**
- ✅ Service Account: `github-workflows@tooling-2026.iam.gserviceaccount.com`
- ✅ Workload Identity Pool: `github-actions-pool-terraform`
- ✅ Workload Identity Provider: `github-actions-provider-terraform`
- ✅ IAM Policy Bindings (secure your repo access)
- ✅ GitHub Repository Variables (auto-set in your repo)

### Step 4: Verify

After `terraform apply`, check your GitHub repo:
1. Go to **Settings** → **Secrets and variables** → **Variables**
2. You should see:
   - `SERVICE_ACCOUNT_EMAIL`
   - `WORKLOAD_IDENTITY_PROVIDER`

Done! ✅ Your authentication is ready to use.

### Terraform Output

After `terraform apply` completes successfully, you'll see:

```
Outputs:

github_organization = "omarfessi"
github_repository = "omarfessi/github-cicd"
service_account_email = "github-workflows@tooling-2026.iam.gserviceaccount.com"
workload_identity_pool_id = "projects/55638060477/locations/global/workloadIdentityPools/github-actions-pool-terraform<4-length-random-string>"
workload_identity_provider_id = "projects/55638060477/locations/global/workloadIdentityPools/github-actions-pool-terraform/providers/github-actions-provider-terraform"
```

These values are now active and GitHub repository variables have been automatically created.

---

## Using in GitHub Actions Workflow

Your workflow (`.github/workflows/gcp-auth.yml`) can now use the auto-created variables:

```yaml
- uses: 'google-github-actions/auth@v3'
  with:
    service_account: ${{ vars.SERVICE_ACCOUNT_EMAIL }}
    workload_identity_provider: ${{ vars.WORKLOAD_IDENTITY_PROVIDER }}
```

See [`.github/workflows/gcp-auth.yml`](.github/workflows/gcp-auth.yml) for a complete example workflow.

---

## Manual Setup (Using gcloud commands)

**Note:** These steps are from [Google GitHub Actions Auth Action](https://github.com/google-github-actions/auth), provided for reference. I preferred to use Terraform above.

## Step 1: Create a Google Cloud Service Account

This service account will be used by your GitHub Actions workflows.

```bash
gcloud iam service-accounts create "github-workflows" \
  --project "tooling-2026" \
  --display-name "GitHub Actions Service Account"
```

**Your values:**
- Service Account Email: `github-workflows@tooling-2026.iam.gserviceaccount.com`
- Project ID: `tooling-2026`

## Step 2: Create a Workload Identity Pool

The pool is a container that manages external workloads (GitHub Actions) authenticating to GCP.
The pool id has 30 days grace after deletion, so it cannot be used especially if you intend to provision such resources with Terraform, I used a random 4 length string suffix to overcome this constraint.

```bash
gcloud iam workload-identity-pools create "github-actions-pool<4-length-random-string>" \
  --project="tooling-2026" \
  --location="global" \
  --display-name="GitHub Actions Pool"
```

## Step 3: Get the Full Workload Identity Pool ID

You'll need this ID for the IAM binding and provider creation. 

```bash
gcloud iam workload-identity-pools describe "github-actions-pool" \
  --project="tooling-2026" \
  --location="global" \
  --format="value(name)"
```

**Output format:**
```
projects/55638060477/locations/global/workloadIdentityPools/github-actions-pool<4-length-random-string>
```

**Save this value** - you'll use it multiple times.

## Step 4: Create a Workload Identity Provider

The provider defines HOW to authenticate (OIDC) and WHICH tokens are accepted (attribute condition).

```bash
gcloud iam workload-identity-pools providers create-oidc "github-actions-provider-v2" \
  --project="tooling-2026" \
  --location="global" \
  --workload-identity-pool="github-actions-pool" \
  --display-name="GitHub Actions OIDC Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == 'omarfessi'" \
  --issuer-uri="https://token.actions.githubusercontent.com"
```

### Understanding Attribute Mapping and Condition

**Attribute Mapping** extracts claims from the GitHub OIDC token:
- `assertion.sub` → GitHub's subject claim
- `assertion.actor` → GitHub user who triggered the workflow
- `assertion.repository` → Full repo path (e.g., `omarfessi/github-cicd`)
- `assertion.repository_owner` → Just the owner name (e.g., `omarfessi`)

**Attribute Condition** acts as a security gate at the pool level:
- `assertion.repository_owner == 'omarfessi'` → Allows ANY repo owned by `omarfessi`
- This is a broad filter; more specific restrictions happen in IAM bindings

## Step 5: Get the Workload Identity Provider Resource Name

Extract the full provider ID for use in GitHub Actions.

```bash
gcloud iam workload-identity-pools providers describe "github-actions-provider-v2" \
  --project="tooling-2026" \
  --location="global" \
  --workload-identity-pool="github-actions-pool<4-length-random-string>" \
  --format="value(name)"
```

**Output format:**
```
projects/55638060477/locations/global/workloadIdentityPools/github-actions-pool<4-length-random-string>/providers/github-actions-provider-v2
```

**Save this value** - you'll need it in your GitHub Actions workflow.

---

## Step 6: Create IAM Policy Binding

This is the **final security layer** that restricts which repository can use the service account.

```bash
gcloud iam service-accounts add-iam-policy-binding "github-workflows@tooling-2026.iam.gserviceaccount.com" \
  --project="tooling-2026" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/55638060477/locations/global/workloadIdentityPools/github-actions-pool<4-length-random-string>/attribute.repository/omarfessi/github-cicd"
```

### Security Layers Explained

| Layer                       | Check                                       | Example                                      |
|-----------------------------|---------------------------------------------|----------------------------------------------|
| **WIP Attribute Condition** | Is the token from my GitHub org?            | `repository_owner == 'omarfessi'`            |
| **IAM Binding**             | Is the token from my specific repo?         | `attribute.repository/omarfessi/github-cicd` |
| **GitHub Permissions**      | Does the OIDC token have `id-token: write`? | Required in workflow permissions             |

All three must pass for authentication to succeed.

## Step 7: Verify the IAM Binding

Check what's actually configured:

```bash
gcloud iam service-accounts get-iam-policy "github-workflows@tooling-2026.iam.gserviceaccount.com" \
  --project="tooling-2026"
```

**Expected output:**
```yaml
bindings:
- members:
  - principalSet://iam.googleapis.com/projects/55638060477/locations/global/workloadIdentityPools/github-actions-pool<4-length-random-string>/attribute.repository/omarfessi/github-cicd
  role: roles/iam.workloadIdentityUser
```

## Step 8: Grant Service Account Permissions

The service account needs permissions to access GCP resources. Example: access a secret in Secret Manager:

```bash
gcloud secrets add-iam-policy-binding "my-secret" \
  --project="tooling-2026" \
  --role="roles/secretmanager.secretAccessor" \
  --member="serviceAccount:github-workflows@tooling-2026.iam.gserviceaccount.com"
```

## Additional Resources

- [Google Cloud Workload Identity Federation Documentation](https://cloud.google.com/docs/authentication/workload-identity-federation)
- [Google GitHub Actions Auth Action](https://github.com/google-github-actions/auth)
- [GitHub OIDC Token Claims](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
