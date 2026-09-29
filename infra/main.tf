terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    # ⚠️ ATENÇÃO: NÃO definir valores fixos aqui no Backend.
    # ⚠️ Configurado dinamicamente via CLI (terraform init -backend-config) no arquivo .github/workflows/azure-terraform-iac.yml
    resource_group_name  = "..." # RG-Terraform-State
    storage_account_name = "..." # tf2gha4suaempresa
    container_name       = "..." # terraform-state
    key                  = "..." # infra.tfstate
  }
}

provider "azurerm" {
  features { }

  resource_providers_to_register = [
    "Microsoft.Communication",       # ACS (era o que faltava)
    "Microsoft.Web",                 # Static Web Apps, Service Plan, Function App
    "Microsoft.Storage",             # Storage Account / Container
    "Microsoft.OperationalInsights", # Log Analytics
    "Microsoft.Insights",            # Application Insights
  ]
}



variable "Project" {
  type        = string
  description = "Nome base do projeto"
}

variable "AppEnv" {
  type        = string
  description = "Ambiente (HMG ou PRD)"
}

variable "CreateResourceLP" {
  type        = bool
  description = "Indica se vai ser Criado um Recurso para a LandingPage"
  default     = null
}

variable "DotNetVersion" {
  type        = string
  description = "Versão do Runtime do Dotnet"
  default     = "10.0"
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

variable "CreateResourceACS" {
  type        = bool
  description = "Indica se serão criados os recursos de e-mail (Azure Communication Services). Opt-in: o chamador passa true para habilitar."
  default     = false
}

variable "CustomDomain" {
  type        = string
  description = "Domínio próprio para envio (ex.: tantagrana.com.br). Vazio ou com menos de 4 caracteres = usa apenas o domínio gerenciado do Azure (DoNotReply@<guid>.azurecomm.net)."
  default     = ""
}

variable "CustomDomainVerified" {       # nova flag, default false
  type    = bool
  default = false
}

variable "StaticWebAppSku" {
  # Sem default de propósito: o valor padrão vive no input StaticWebAppSku do workflow,
  # para haver uma única fonte da verdade.
  type        = string
  description = "Plano (SKU) dos Static Web Apps: Free (gratuito, limitado a 10 por assinatura) ou Standard (pago)."

  validation {
    condition     = contains(["Free", "Standard"], var.StaticWebAppSku)
    error_message = "StaticWebAppSku deve ser Free ou Standard (exatamente assim, com a inicial maiúscula)."
  }
}



locals {
  CreateResourceLP  = (var.CreateResourceLP != null) ? var.CreateResourceLP : var.AppEnv == "PRD"
  CreateResourceACS = var.CreateResourceACS
  CreateCustomDomain= local.CreateResourceACS && var.CustomDomain != null && length(var.CustomDomain) >= 4
  LinkCustomDomain  = local.CreateCustomDomain && var.CustomDomainVerified
  prefix            = "${var.Project}-${var.AppEnv}"
  resource_group    = "RG-${local.prefix}"
  communication     = "${local.prefix}"
  email_service     = "${local.prefix}"
  landing_page      = "${local.prefix}-landing"
  blazor_webapp     = "${local.prefix}"
  storage_account   = lower(replace(local.prefix, "-", "4"))
  storage_container = lower(local.prefix)
  log_analytics     = "${local.prefix}"
  app_insights      = "${local.prefix}"
  service_plan      = "${local.prefix}"
  function_app      = "${local.prefix}"
  location1         = "East US"
  location2         = "East US 2"
  locationAcs       = "Brazil" # "Residência dos dados dos recursos ACS. Valores válidos: United States, Europe, Brazil, etc. 'United States' é o mais amplamente ofertado;
}



resource "azurerm_resource_group" "main" {
  name                       = local.resource_group
  location                   = local.location1
}



resource "azurerm_communication_service" "main" {
  count                      = local.CreateResourceACS ? 1 : 0

  name                       = local.communication
  resource_group_name        = azurerm_resource_group.main.name
  data_location              = local.locationAcs
}



resource "azurerm_email_communication_service" "main" {
  count                      = local.CreateResourceACS ? 1 : 0

  name                       = local.email_service
  resource_group_name        = azurerm_resource_group.main.name
  data_location              = local.locationAcs
}



resource "azurerm_email_communication_service_domain" "managed" {
  # Domínio gerenciado do Azure: instantâneo, sem DNS. Remetente: DoNotReply@<from_sender_domain>.
  count                      = local.CreateResourceACS ? 1 : 0

  name                       = "AzureManagedDomain"
  domain_management          = "AzureManaged"
  email_service_id           = azurerm_email_communication_service.main[0].id
}



resource "azurerm_communication_service_email_domain_association" "managed" {
  count                      = local.CreateResourceACS ? 1 : 0

  communication_service_id   = azurerm_communication_service.main[0].id
  email_service_domain_id    = azurerm_email_communication_service_domain.managed[0].id
}



resource "azurerm_email_communication_service_domain" "custom" {
  # Domínio próprio (opcional): criado só quando CustomDomain tem >= 4 caracteres. Após o apply, publicar os verification_records (TXT/SPF/DKIM) no DNS e verificar no portal.
  count                      = local.CreateCustomDomain ? 1 : 0

  name                       = var.CustomDomain
  domain_management          = "CustomerManaged"
  email_service_id           = azurerm_email_communication_service.main[0].id
}



resource "azurerm_communication_service_email_domain_association" "custom" {
  count                      = local.LinkCustomDomain ? 1 : 0

  communication_service_id   = azurerm_communication_service.main[0].id
  email_service_domain_id    = azurerm_email_communication_service_domain.custom[0].id
}



resource "azurerm_email_communication_service_domain_sender_username" "noreply" {
  count                      = local.CreateCustomDomain ? 1 : 0

  name                       = "noreply"
  email_service_domain_id    = azurerm_email_communication_service_domain.custom[0].id
  display_name               = var.Project
}



resource "azurerm_static_web_app" "landing_page" {
  count                      = local.CreateResourceLP ? 1 : 0

  name                       = local.landing_page
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location2
  sku_tier                   = var.StaticWebAppSku
  sku_size                   = var.StaticWebAppSku

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
  sku_tier                   = var.StaticWebAppSku
  sku_size                   = var.StaticWebAppSku

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
  daily_quota_gb             = 0.025
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
  runtime_version            = var.DotNetVersion
  maximum_instance_count     = 50
  instance_memory_in_mb      = 4096

  site_config {
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    cors {
      allowed_origins        = ["*"]
    }
  }

  app_settings = merge(
    {
      "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    },
    local.CreateResourceACS ? {
      "Acs_ConnectionString" = azurerm_communication_service.main[0].primary_connection_string
    } : {}
  )

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



output "acs_managed_sender_domain" {
  description = "Domínio gerenciado; remetente de teste = DoNotReply@<este-valor>. Use em Email_FromAddress (dev/HMG)."
  value       = one(azurerm_email_communication_service_domain.managed[*].from_sender_domain)
}

output "acs_custom_domain_dns_records" {
  description = "Registros DNS (TXT/SPF/DKIM) a publicar para verificar o domínio próprio (quando CustomDomain tem >= 4 caracteres)."
  value       = one(azurerm_email_communication_service_domain.custom[*].verification_records)
}
