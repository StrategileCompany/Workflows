terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "RG-Terraform-State"
    storage_account_name = "gh4ctions7erraform5tate"
    container_name       = "terraform-state"
    key                  = "infra.tfstate"
  }
}

provider "azurerm" {
  features {}
}



variable "project" {
  type        = string
  description = "Nome base do projeto"
}

variable "env" {
  type        = string
  description = "Ambiente (HMG ou PRD)"
}

variable "ConnectionStringType" {
  type        = string
  description = "Default Connection String Type"
  default     = "SQLServer"
}

variable "ConnectionStringName" {
  type        = string
  description = "Default Connection String Name"
  default     = "Default"
}

variable "ConnectionStringValue" {
  type        = string
  description = "Default Connection String Value"
  sensitive   = true
}



locals {
  location1         = "East US"
  location2         = "East US 2"

  project           = var.project
  env               = var.env

  prefix            = "${local.project}-${local.env}"
  resource_group    = "RG-${local.prefix}"
  landing_page      = "${local.prefix}-landing"
  blazor_webapp     = "${local.prefix}-webapp"
  storage_account   = lower(replace(local.prefix, "-", ""))
  storage_container = lower(local.prefix)
  log_analytics     = "${local.prefix}"
  app_insights      = "${local.prefix}"
  service_plan      = "${local.prefix}"
  function_app      = "${local.prefix}"
}



resource "azurerm_resource_group" "main" {
  name                       = local.resource_group
  location                   = local.location1
}



resource "azurerm_static_web_app" "landing_page" {
  name                       = local.landing_page
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location2
  sku_tier                   = "Free"
  sku_size                   = "Free"

  lifecycle {
    ignore_changes = [
      repository_branch,
      repository_url
    ]
  }
}



resource "azurerm_static_web_app" "blazor_webapp" {
  name                       = local.blazor_webapp
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location2
  sku_tier                   = "Free"
  sku_size                   = "Free"

  lifecycle {
    ignore_changes = [
      repository_branch,
      repository_url
    ]
  }
}



resource "azurerm_storage_account" "main" {
  name                       = local.storage_account
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location1
  account_tier               = "Standard"
  account_replication_type   = "LRS"
}



resource "azurerm_storage_container" "main" {
  name                       = local.storage_container
  storage_account_id         = azurerm_storage_account.main.id
  container_access_type      = "private"
}



resource "azurerm_log_analytics_workspace" "main" {
  name                       = local.log_analytics
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location1
  sku                        = "PerGB2018"
  retention_in_days          = 30
}



resource "azurerm_application_insights" "main" {
  name                       = local.app_insights
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location1
  workspace_id               = azurerm_log_analytics_workspace.main.id
  application_type           = "web"
}



resource "azurerm_service_plan" "main" {
  name                       = local.service_plan
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location1
  sku_name                   = "FC1"
  os_type                    = "Linux"
}



resource "azurerm_function_app_flex_consumption" "main" {
  name                       = local.function_app
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location1
  service_plan_id            = azurerm_service_plan.main.id

  storage_container_type     = "blobContainer"
  storage_container_endpoint = "${azurerm_storage_account.main.primary_blob_endpoint}${azurerm_storage_container.main.name}"
  storage_authentication_type= "StorageAccountConnectionString"
  storage_access_key         = azurerm_storage_account.main.primary_access_key
  runtime_name               = "dotnet-isolated"
  runtime_version            = "10.0"
  maximum_instance_count     = 50
  instance_memory_in_mb      = 4096

  site_config {
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    cors {
      allowed_origins        = ["*"]
    }
  }

  app_settings = {
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
  }

  connection_string {
    type  = var.ConnectionStringType
    name  = var.ConnectionStringName
    value = var.ConnectionStringValue
  }

  lifecycle {
    ignore_changes = [
      app_settings["APPLICATIONINSIGHTS_CONNECTION_STRING"],
      tags
    ]
  }
}



output "landing_page_deployment_token" {
  value     = azurerm_static_web_app.landing_page.api_key
  sensitive = true
}



output "blazor_webapp_deployment_token" {
  value     = azurerm_static_web_app.blazor_webapp.api_key
  sensitive = true
}

