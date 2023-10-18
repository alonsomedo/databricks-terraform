# Azure Databricks with Terraform

This terraform code performs a simple deployment of Azure Databricks following medallion architecture. 

The main resources to be deployed are the following:
- Azure Resource Group
- Azure Storage Account
- Azure Service Principal
- Azure Key Vault
- Azure Databricks Workspace
- Databricks Cluster

(*) We won't use mounting because it's a deprecated pattern.
