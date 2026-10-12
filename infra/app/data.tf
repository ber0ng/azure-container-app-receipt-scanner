# Blob storage: receipt images
resource "azurerm_storage_account" "storage_receipt" {
  name                            = "st${var.project}${var.environment}${random_string.suffix.result}"
  resource_group_name             = data.azurerm_resource_group.env_rg.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false # managed identity only
  allow_nested_items_to_be_public = false

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
  tags = local.tags

}

resource "azurerm_storage_container" "receipts" {
  name                  = "receipts" # matches STORAGE_CONTAINER default in api + worker
  storage_account_id    = azurerm_storage_account.storage_receipt.id
  container_access_type = "private"
}

# Service bus: job queue
resource "azurerm_servicebus_namespace" "service_bus_namespace" {
  name                = "sb-${local.name}-${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.env_rg.name
  location            = var.location
  sku                 = "Basic"
  minimum_tls_version = "1.2"
  tags                = local.tags
}

resource "azurerm_servicebus_queue" "sb_receipts_queue" {
  name                                 = "receipts"
  namespace_id                         = azurerm_servicebus_namespace.service_bus_namespace.id
  max_delivery_count                   = 3 # matches max_attempts in the worker
  lock_duration                        = "PT1M"
  default_message_ttl                  = "P1D"
  dead_lettering_on_message_expiration = true
}

# Used only by the keda scaler to read the queue length. Scoped to this one queue
# The worker itself receives messages with its managed identity, not this key
resource "azurerm_servicebus_queue_authorization_rule" "servicebus_keda" {
  name     = "keda-scaler"
  queue_id = azurerm_servicebus_queue.sb_receipts_queue.id
  listen   = true
  send     = true # azure requires listen + send when manage is on
  manage   = true # keda reads queue runtime properties, which needs Manage
}

# Cosmos DB: receipt records
resource "azurerm_cosmosdb_account" "cosmos_account" {
  name                = "cosmos-${local.name}-${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.env_rg.name
  location            = var.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  free_tier_enabled   = var.cosmos_free_tier

  # free tier uses provisioned throughput; everything else is serverless
  dynamic "capabilities" {
    for_each = var.cosmos_free_tier ? [] : ["EnableServerless"]
    content {
      name = capabilities.value
    }
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  tags = local.tags
}

resource "azurerm_cosmosdb_sql_database" "cosmos_db" {
  name                = "receiptsdb"
  resource_group_name = data.azurerm_resource_group.env_rg.name
  account_name        = azurerm_cosmosdb_account.cosmos_account.name
  throughput          = var.cosmos_free_tier ? 400 : null
}

resource "azurerm_cosmosdb_sql_container" "cosmos_container" {
  name                  = "receipts"
  resource_group_name   = data.azurerm_resource_group.env_rg.name
  account_name          = azurerm_cosmosdb_account.cosmos_account.name
  database_name         = azurerm_cosmosdb_sql_database.cosmos_db.name
  partition_key_paths   = ["/id"]
  partition_key_version = 2
}
