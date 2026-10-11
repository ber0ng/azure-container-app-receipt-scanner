output "github_repo_variables" {
  description = "Repository-level variables"
  value = {
    AZURE_TENANT_ID         = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID   = var.subscription_id
    TFSTATE_RESOURCE_GROUP  = azurerm_resource_group.tfstate_rg.name
    TFSTATE_STORAGE_ACCOUNT = azurerm_storage_account.tfstate_storage_account.name
    ACR_NAME                = azurerm_container_registry.shared_acr.name
    ACR_LOGIN_SERVER        = azurerm_container_registry.shared_acr.login_server
  }
}

output "github_environment_variables" {
  description = "Per env Github variables"
  value = {
    for env in var.environments : env => {
      AZURE_CLIENT_ID   = azuread_application.github_identities[env].client_id
      TFSTATE_CONTAINER = azurerm_storage_container.tfstate_storage_container[env].name
      RESOURCE_GROUP    = azurerm_resource_group.env_rg[env].name
    }
  }
}
