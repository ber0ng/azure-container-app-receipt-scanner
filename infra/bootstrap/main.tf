terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.4"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true # shared keys are disabled on the the state account
}

provider "azuread" {}

data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

locals {
  tags = {
    project    = var.project
    managed_by = "Terraform"
  }

  envs      = toset(var.environments)
  build_env = var.environments[0] #images are built once here, then promoted

  acr_pull_role_id = "7f951dda-4ed3-4680-a7ca-43fe172d538d" # built-in AcrPull"

  # which github workflow runs may log in as each environments identity
  federated_credentials = merge(
    {
      for env in var.environments : "${env}-environment" => {
        env     = env
        name    = "github-environment-${env}"
        subject = "repo:${var.github_repo}:environment:${env}"
      }
    },
    # terraform plan on PR runs against the first env
    {
      "${local.build_env}-pull-request" = {
        env     = local.build_env
        name    = "github-pull-request"
        subject = "repo:${var.github_repo}:pull_request"
      }
    }
  )
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# Terraform remote state (one container per env)
resource "azurerm_resource_group" "tfstate_rg" {
  name     = "rg-${var.project}-tfstate"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate_storage_account" {
  name                            = "st${var.project}tf${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.tfstate_rg.name
  location                        = azurerm_resource_group.tfstate_rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false # entra id auth only
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate_storage_container" {
  for_each = local.envs

  name                  = "tfstate-${each.key}"
  storage_account_id    = azurerm_storage_account.tfstate_storage_account.id
  container_access_type = "private"
}

# Shared: container registry (build once, promote after)
resource "azurerm_resource_group" "shared_rg" {
  name     = "rg-${var.project}-shared"
  location = var.location
  tags     = local.tags
}

resource "azurerm_container_registry" "shared_acr" {
  name                = "acr${var.project}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.shared_rg.name
  location            = azurerm_resource_group.shared_rg.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

# Per env rg 
resource "azurerm_resource_group" "env_rg" {
  for_each = local.envs
  name     = "rg-${var.project}-${each.key}"
  location = var.location
  tags     = merge(local.tags, { environment = each.key })
}

# Per env github identities (OIDC)
resource "azuread_application" "github_identities" {
  for_each     = local.envs
  display_name = "gh-${var.project}-${each.key}"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "github_sp" {
  for_each  = local.envs
  client_id = azuread_application.github_identities[each.key].client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_federated_identity_credential" "github_federated_creds" {
  for_each       = local.federated_credentials
  application_id = azuread_application.github_identities[each.value.env].id
  display_name   = each.value.name
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = each.value.subject
}

# Permissions: each identity only touches its own env
resource "azurerm_role_assignment" "env_contributor" {
  for_each             = local.envs
  scope                = azurerm_resource_group.env_rg[each.key].id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_sp[each.key].object_id
}

# Terraform grant the app's managed identity its roles insdie the env RG
resource "azurerm_role_assignment" "env_rbac_admin" {
  for_each             = local.envs
  scope                = azurerm_resource_group.env_rg[each.key].id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azuread_service_principal.github_sp[each.key].object_id
}

# Own state container only: dev's pipelien can't get staging or prod token; vice versa
resource "azurerm_role_assignment" "env_stae" {
  for_each             = local.envs
  scope                = azurerm_storage_container.tfstate_storage_container[each.key].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github_sp[each.key].object_id
}

# Read the shared registry 
resource "azurerm_role_assignment" "env_shared_reader" {
  for_each             = local.envs
  scope                = azurerm_resource_group.shared_rg.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.github_sp[each.key].object_id
}

# Each env may grant AcrPull on the registry to its app identity; nothing else
resource "azurerm_role_assignment" "env_acr_pull_delegation" {
  for_each             = local.envs
  scope                = azurerm_container_registry.shared_acr.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azuread_service_principal.github_sp[each.key].object_id
  condition_version    = "2.0"
  condition            = <<-EOT
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
      )
      OR
      (
        @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.acr_pull_role_id}}
      )
    )
    AND
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
      )
      OR
      (
        @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.acr_pull_role_id}}
      )
    )
  EOT
}

# Only build the env pushes images
resource "azurerm_role_assignment" "build_acr_push" {
  scope                = azurerm_container_registry.shared_acr.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github_sp[local.build_env].object_id
}

# Me: access to every env state from my pc
resource "azurerm_role_assignment" "me_state" {
  scope                = azurerm_storage_account.tfstate_storage_account.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
