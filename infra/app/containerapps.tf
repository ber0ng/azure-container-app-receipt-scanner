locals {
  acr_server = data.azurerm_container_registry.shared_acr.login_server
}

resource "azurerm_container_app_environment" "aca_env" {
  name                       = "cae-${local.name}"
  resource_group_name        = data.azurerm_resource_group.env_rg.name
  location                   = var.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id
  tags                       = local.tags
}

# API: container app with public ingress
resource "azurerm_container_app" "api_aca" {
  name                         = "ca-${local.name}-api"
  container_app_environment_id = azurerm_container_app_environment.aca_env.id
  resource_group_name          = data.azurerm_resource_group.env_rg.name
  revision_mode                = "Single"
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.api_app_identity.id]
  }

  registry {
    server   = local.acr_server
    identity = azurerm_user_assigned_identity.api_app_identity.id
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.api_min_replicas
    max_replicas = var.api_max_replicas

    container {
      name   = "api"
      image  = "${local.acr_server}/receipt-api:${var.initial_image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.api_app_identity.client_id
      }

      env {
        name  = "STORAGE_ACCOUNT_URL"
        value = azurerm_storage_account.storage_receipt.primary_blob_endpoint
      }

      env {
        name  = "SERVICEBUS_NAMESPACE"
        value = "${azurerm_servicebus_namespace.service_bus_namespace.name}.servicebus.windows.net"
      }

      env {
        name  = "COSMOS_ENDPOINT"
        value = azurerm_cosmosdb_account.cosmos_account.endpoint
      }

      liveness_probe {
        transport = "HTTP"
        port      = 3000
        path      = "/healthz"
      }

      readiness_probe {
        transport = "HTTP"
        port      = 3000
        path      = "/healthz"
      }
    }

    http_scale_rule {
      name                = "http-concurrency"
      concurrent_requests = "20"
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image] # the app pipeline owns the image
  }

  depends_on = [
    azurerm_role_assignment.api_acr_pull,
    azurerm_role_assignment.api_blob,
    azurerm_role_assignment.api_queue_send,
    azurerm_cosmosdb_sql_role_assignment.api_cosmos
  ]
}

# Worker: container app job, started by keda when messages arrive
resource "azurerm_container_app_job" "worker_job_aca" {
  name                         = "caj-${local.name}-worker"
  location                     = var.location
  resource_group_name          = data.azurerm_resource_group.env_rg.name
  container_app_environment_id = azurerm_container_app_environment.aca_env.id
  replica_timeout_in_seconds   = 600
  replica_retry_limit          = 1
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.worker_app_identity.id]
  }

  registry {
    server   = local.acr_server
    identity = azurerm_user_assigned_identity.worker_app_identity.id
  }

  secret {
    name  = "servicebus-keda"
    value = azurerm_servicebus_queue_authorization_rule.servicebus_keda.primary_connection_string
  }

  event_trigger_config {
    parallelism              = 1
    replica_completion_count = 1

    scale {
      min_executions              = 0
      max_executions              = var.worker_max_executions
      polling_interval_in_seconds = 30

      rules {
        name             = "servicebus-queue"
        custom_rule_type = "azure-servicebus"
        metadata = {
          namespace    = azurerm_servicebus_namespace.service_bus_namespace.name
          queueName    = azurerm_servicebus_queue.sb_receipts_queue.name
          messageCount = "5"
        }

        authentication {
          secret_name       = "servicebus-keda"
          trigger_parameter = "connection"
        }
      }
    }
  }

  template {
    container {
      name   = "worker"
      image  = "${local.acr_server}/receipt-worker:${var.initial_image_tag}"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.worker_app_identity.client_id
      }

      env {
        name  = "WORKER_MODE"
        value = "job" # drain the queue then exit
      }

      env {
        name  = "EXTRACTOR"
        value = "azure"
      }

      env {
        name  = "DOCINTEL_ENDPOINT"
        value = azurerm_cognitive_account.docintel.endpoint
      }

      env {
        name  = "STORAGE_ACCOUNT_URL"
        value = azurerm_storage_account.storage_receipt.primary_blob_endpoint
      }

      env {
        name  = "SERVICEBUS_NAMESPACE"
        value = "${azurerm_servicebus_namespace.service_bus_namespace.name}.servicebus.windows.net"
      }

      env {
        name  = "COSMOS_ENDPOINT"
        value = azurerm_cosmosdb_account.cosmos_account.endpoint
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [
    azurerm_role_assignment.worker_acr_pull,
    azurerm_role_assignment.worker_blob,
    azurerm_role_assignment.worker_queue_receive,
    azurerm_role_assignment.worker_docintel,
    azurerm_cosmosdb_sql_role_assignment.worker_cosmos
  ]
}
