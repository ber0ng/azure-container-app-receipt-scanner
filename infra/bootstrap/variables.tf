variable "subscription_id" {
  description = "Azure subscription"
  type        = string
}

variable "github_repo" {
  description = "Github repo as it appears in the OIDC sub claim, e.g. owner@<owner_id>/repo@<repo_id>"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "rcptscan"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.project))
    error_message = "Use 3-10 lowercase letters or digits (storage account naming rules)."
  }
}

variable "environments" {
  description = "Environment name"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

variable "location" {
  type    = string
  default = "eastus"
}
