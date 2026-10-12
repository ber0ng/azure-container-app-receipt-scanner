variable "subscription_id" {
  type = string
}

variable "project" {
  type    = string
  default = "rcptscan"
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod"
  }
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "acr_name" {
  description = "Shared ACR created by bootstrap"
  type        = string
}

variable "cosmos_free_tier" {
  description = "Use the cosmos db free tier"
  type        = bool
  default     = false
}

variable "docintel_sku" {
  description = "F0 - free (one per subs) S0 - pay per page"
  type        = string
  default     = "S0"
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "log_daily_cap_gb" {
  description = "Daily log analytics ingestion cap"
  type        = number
  default     = 0.5
}

variable "initial_image_tag" {
  description = "Image tag used when the app/job is first created. After that the pipeline owns the image tag"
  type        = string
  default     = "bootstrap"
}

variable "api_min_replicas" {
  description = "0 = scale to zero (cold starts). 1 = always warm"
  type        = number
  default     = 0
}

variable "api_max_replicas" {
  type    = number
  default = 2
}

variable "worker_max_executions" {
  description = "Max parallel worker job executions KEDA can start"
  type        = number
  default     = 4
}
