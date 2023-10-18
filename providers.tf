terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.72.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "1.27.0"
    }
    azuread = {
      source = "hashicorp/azuread"
      version = "2.43.0"
    }
    time = {
      source = "hashicorp/time"
      version = "0.9.1"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

provider "azuread" {
  # Configuration options
}

provider "time" {
  # Configuration options
}

provider "databricks" {
  host = azurerm_databricks_workspace.dbwdata01.workspace_url
  azure_workspace_resource_id = azurerm_databricks_workspace.dbwdata01.id
}


