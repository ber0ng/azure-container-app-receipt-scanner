resource "azurerm_cognitive_account" "docintel" {
  name                  = "di-${local.name}"
  resource_group_name   = data.azurerm_resource_group.env_rg.name
  location              = var.location
  kind                  = "FormRecognizer"
  sku_name              = var.docintel_sku
  custom_subdomain_name = "di-${local.name}-${random_string.suffix.result}"
  local_auth_enabled    = false
  tags                  = local.tags
}
