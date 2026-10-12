locals {
  name      = "${var.project}-${var.environment}"
  shared_rg = "rg-${var.project}-shared"

  tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "Terraform"
  }
}

# Created by bootstrap; config looks them up
data "azurerm_resource_group" "env_rg" {
  name = "rg-${local.name}"
}

data "azurerm_container_registry" "shared_acr" {
  name                = var.acr_name
  resource_group_name = local.shared_rg
}

# Suffix for names that must be globally unique
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# Logs
resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "law-${local.name}"
  resource_group_name = data.azurerm_resource_group.env_rg.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.log_daily_cap_gb
  tags                = local.tags
}

# App identities (one per component, least privilege)
resource "azurerm_user_assigned_identity" "api_app_identity" {
  name                = "id-${local.name}-api"
  resource_group_name = data.azurerm_resource_group.env_rg.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "worker_app_identity" {
  name                = "id-${local.name}-worker"
  resource_group_name = data.azurerm_resource_group.env_rg.name
  location            = var.location
  tags                = local.tags
}


