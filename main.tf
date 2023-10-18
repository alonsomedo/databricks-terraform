data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}
data "azurerm_subscription" "primary" {}

data "azuread_service_principal" "azuredatabricks" {
  display_name = "AzureDatabricks"
}

locals {
  stgaccname = "${var.stgaccname}${var.company}${var.env}01"
}

# Create main resource group
resource "azurerm_resource_group" "rgdata01" {
  name     = "rgdata${var.company}${var.env}01"
  location = "${var.default_location}"
}

# Create storage account
resource "azurerm_storage_account" "stacdata01" {
  name                     = local.stgaccname
  resource_group_name      = azurerm_resource_group.rgdata01.name
  location                 = azurerm_resource_group.rgdata01.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true

  blob_properties {
    delete_retention_policy {
      days = 1
    }
    container_delete_retention_policy {
      days = 1
    }
  }

  tags = {
    environment = "${var.env}"
  }
}

# Create containers for bronze, silver and gold layer
resource "azurerm_storage_container" "ctdatabronze" {
  name                  = "ctdatabronze"
  storage_account_name  = azurerm_storage_account.stacdata01.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "ctdatasilver" {
  name                  = "ctdatasilver"
  storage_account_name  = azurerm_storage_account.stacdata01.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "ctdatagold" {
  name                  = "ctdatagold"
  storage_account_name  = azurerm_storage_account.stacdata01.name
  container_access_type = "private"
}

# Create databricks workspace
resource "azurerm_databricks_workspace" "dbwdata01" {
  name                = "dbwdata${var.company}${var.env}01"
  resource_group_name = azurerm_resource_group.rgdata01.name
  location            = azurerm_resource_group.rgdata01.location
  sku                 = "standard"

  tags = {
    environment = "${var.env}"
  }
}

# Create Key vault
resource "azurerm_key_vault" "kvdatabricks" {
  name                        = "kv${var.company}${var.env}"
  location                    = azurerm_resource_group.rgdata01.location
  resource_group_name         = azurerm_resource_group.rgdata01.name
  enable_rbac_authorization   = false
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  # Access policy principal account
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = ["Get", "Create", "Delete", "List", "Restore", "Recover", "UnwrapKey", "WrapKey", "Purge", "Encrypt", "Decrypt", "Sign", "Verify", "Release", "Rotate", "GetRotationPolicy", "SetRotationPolicy"]
    secret_permissions = ["Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"]
    storage_permissions = ["Backup", "Delete", "DeleteSAS", "Get", "GetSAS", "List", "ListSAS", "Purge", "Recover", "RegenerateKey", "Restore", "Set", "SetSAS", "Update"]

  }

  # Access policy for AzureDatabricks Account
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azuread_service_principal.azuredatabricks.object_id
    
    secret_permissions = ["Get", "List"]
  }

  sku_name = "standard"
}

# Create Application
resource "azuread_application" "databricksapp" {
  display_name = "svcprdatabricks${var.company}${var.env}"
  owners       = [data.azuread_client_config.current.object_id]
  sign_in_audience = "AzureADMyOrg"
}

# Create Service Principal
resource "azuread_service_principal" "databricksapp" {
  application_id               = azuread_application.databricksapp.application_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]

  feature_tags {
    enterprise = true
    gallery    = true
  }
}


resource "time_rotating" "two_years" {
  rotation_days = 720
}

# Create secret for App
resource "azuread_application_password" "databricksapp" {
  depends_on = [ azurerm_key_vault.kvdatabricks ]
  display_name         = "databricksapp App Password"
  application_object_id = azuread_application.databricksapp.object_id
  
  rotate_when_changed = {
    rotation = time_rotating.two_years.id
  }
}

# Assign role to service principal
resource "azurerm_role_assignment" "databricksapp" {
  scope                = azurerm_storage_account.stacdata01.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.databricksapp.id
}


# Store secret, clientid and tenantid in secret
resource "azurerm_key_vault_secret" "databricksappsecret" {
  name         = "${var.secretsname["databricksappsecret"]}"
  value        = azuread_application_password.databricksapp.value
  key_vault_id = azurerm_key_vault.kvdatabricks.id
}

resource "azurerm_key_vault_secret" "databricksappclientid" {
  name         = "${var.secretsname["databricksappclientid"]}"
  value        = azuread_application.databricksapp.application_id
  key_vault_id = azurerm_key_vault.kvdatabricks.id
}

resource "azurerm_key_vault_secret" "tenantid" {
  name         = "${var.secretsname["tenantid"]}"
  value        = data.azurerm_client_config.current.tenant_id
  key_vault_id = azurerm_key_vault.kvdatabricks.id
}


# Create Databricks Cluster
data "databricks_node_type" "smallest" {
  depends_on = [ azurerm_databricks_workspace.dbwdata01 ]
  local_disk = true
  category   = "General Purpose"
}

data "databricks_spark_version" "latest" {
  depends_on = [ azurerm_databricks_workspace.dbwdata01 ]
  latest = true
  long_term_support = true
}

# Grab secrets from azure key vault
data "azurerm_key_vault_secret" "databricksappclientid" {
  depends_on = [ azurerm_key_vault_secret.databricksappclientid ]
  name         = "${var.secretsname["databricksappclientid"]}"
  key_vault_id = azurerm_key_vault.kvdatabricks.id
}

data "azurerm_key_vault_secret" "databricksappsecret" {
  depends_on = [ azurerm_key_vault_secret.databricksappsecret ]
  name         = "${var.secretsname["databricksappsecret"]}"
  key_vault_id = azurerm_key_vault.kvdatabricks.id
}

data "azurerm_key_vault_secret" "tenantid" {
  depends_on = [ azurerm_key_vault_secret.tenantid ]
  name         = "${var.secretsname["tenantid"]}"
  key_vault_id = azurerm_key_vault.kvdatabricks.id
}

# Create Databricks Scope
resource "databricks_secret_scope" "dbwscope" {
  depends_on = [ azurerm_databricks_workspace.dbwdata01, azurerm_key_vault.kvdatabricks ]
  name = var.dbwscope
  initial_manage_principal = "users"
  
  keyvault_metadata {
    resource_id = azurerm_key_vault.kvdatabricks.id
    dns_name    = azurerm_key_vault.kvdatabricks.vault_uri
  }
}

# Create Single Node Cluster
resource "databricks_cluster" "dbcluster01" {
  depends_on              = [ databricks_secret_scope.dbwscope, data.azurerm_key_vault_secret.databricksappsecret ]
  cluster_name            = "dbcluster${var.env}01"
  num_workers             = 0
  spark_version           = data.databricks_spark_version.latest.id # Other possible values ("13.3.x-scala2.12", "11.2.x-cpu-ml-scala2.12", "7.0.x-scala2.12")
  node_type_id            = data.databricks_node_type.smallest.id # Other possible values ("Standard_F4", "Standard_DS3_v2")
  autotermination_minutes = 20
  
  spark_conf = {
    "spark.databricks.cluster.profile" : "singleNode"
    "spark.master" : "local[*]"

    "fs.azure.account.auth.type.${local.stgaccname}.dfs.core.windows.net": "OAuth"
    "fs.azure.account.oauth.provider.type.${local.stgaccname}.dfs.core.windows.net": "org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider"
    "fs.azure.account.oauth2.client.id.${local.stgaccname}.dfs.core.windows.net": "${data.azurerm_key_vault_secret.databricksappclientid.value}"
    "fs.azure.account.oauth2.client.secret.${local.stgaccname}.dfs.core.windows.net": "{{secrets/${var.dbwscope}/${var.secretsname["databricksappsecret"]}}}"
    "fs.azure.account.oauth2.client.endpoint.${local.stgaccname}.dfs.core.windows.net": "https://login.microsoftonline.com/${data.azurerm_key_vault_secret.tenantid.value}/oauth2/token"
  }

  custom_tags = {
    "ResourceClass" = "SingleNode"
  }

}

# Creater multinode cluster
# resource "databricks_cluster" "dbcluster02" {
#   depends_on              = [azurerm_databricks_workspace.dbwdata01]
#   cluster_name            = "dbcluster${var.env}01"
#   num_workers             = 1
#   spark_version           = data.databricks_spark_version.latest.id
#   node_type_id            = data.databricks_node_type.smallest.id
#   autotermination_minutes = 20
  
#   autoscale {
#     min_workers = 1
#     max_workers = 1
#   }

# }

# # Service Principal Password
# resource "azuread_service_principal_password" "databricksapp" {
#   display_name         = "databricksapp Service Principal Secret"
#   service_principal_id = azuread_service_principal.databricksapp.object_id
  
#   rotate_when_changed = {
#     rotation = time_rotating.two_years.id
#   }
# }
