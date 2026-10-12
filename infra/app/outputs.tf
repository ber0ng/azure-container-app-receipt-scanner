output "resource_group" {
  value = data.azurerm_resource_group.env_rg.name
}

output "container_app_environment_id" {
  value = azurerm_container_app_environment.aca_env.id
}

output "acr_login_server" {
  value = data.azurerm_container_registry.shared_acr.login_server
}

output "api_identity_client_id" {
  value = azurerm_user_assigned_identity.api_app_identity.client_id
}

output "worker_identity_client_id" {
  value = azurerm_user_assigned_identity.worker_app_identity.client_id
}

# these map straight onto app's env var
output "app_settings" {
  value = {
    STORAGE_ACCOUNT_URL  = azurerm_storage_account.storage_receipt.primary_blob_endpoint
    SERVICEBUS_NAMESPACE = "${azurerm_servicebus_namespace.service_bus_namespace.name}.servicebus.windows.net"
    COSMOS_ENDPOINT      = azurerm_cosmosdb_account.cosmos_account.endpoint
    DOCINTEL_ENDPOINT    = azurerm_cognitive_account.docintel.endpoint
  }
}

output "api_url" {
  value = "https://${azurerm_container_app.api_aca.ingress[0].fqdn}"
}

# the app pipeline needs these to deploy new images
output "api_app_name" {
  value = azurerm_container_app.api_aca.name
}

output "worker_job_name" {
  value = azurerm_container_app_job.worker_job_aca.name
}
