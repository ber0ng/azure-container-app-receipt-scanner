locals {
  cosmos_data_contributor = "${azurerm_cosmosdb_account.cosmos_account.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
}

# API: upload images, create records, queue jobs
resource "azurerm_role_assignment" "api_blob" {
  scope                = azurerm_storage_account.storage_receipt.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.api_app_identity.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "api_queue_send" {
  scope                = azurerm_servicebus_queue.sb_receipts_queue.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.api_app_identity.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_cosmosdb_sql_role_assignment" "api_cosmos" {
  resource_group_name = data.azurerm_resource_group.env_rg.name
  account_name        = azurerm_cosmosdb_account.cosmos_account.name
  role_definition_id  = local.cosmos_data_contributor
  principal_id        = azurerm_user_assigned_identity.api_app_identity.principal_id
  scope               = azurerm_cosmosdb_account.cosmos_account.id
}

resource "azurerm_role_assignment" "api_acr_pull" {
  scope                = data.azurerm_container_registry.shared_acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.api_app_identity.principal_id
  principal_type       = "ServicePrincipal"
}

# Worker: read images, consume jobs, call docintel, update records
resource "azurerm_role_assignment" "worker_blob" {
  scope                = azurerm_storage_account.storage_receipt.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.worker_app_identity.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "worker_queue_receive" {
  scope                = azurerm_servicebus_queue.sb_receipts_queue.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.worker_app_identity.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "worker_docintel" {
  scope                = azurerm_cognitive_account.docintel.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.worker_app_identity.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_cosmosdb_sql_role_assignment" "worker_cosmos" {
  resource_group_name = data.azurerm_resource_group.env_rg.name
  account_name        = azurerm_cosmosdb_account.cosmos_account.name
  role_definition_id  = local.cosmos_data_contributor
  principal_id        = azurerm_user_assigned_identity.worker_app_identity.principal_id
  scope               = azurerm_cosmosdb_account.cosmos_account.id
}

resource "azurerm_role_assignment" "worker_acr_pull" {
  scope                = data.azurerm_container_registry.shared_acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.worker_app_identity.principal_id
  principal_type       = "ServicePrincipal"
}

