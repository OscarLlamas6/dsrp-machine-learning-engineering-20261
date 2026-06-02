# Restricciones de versión para Terraform y los providers.
# Mantener pineado evita que un `terraform init` futuro traiga un major nuevo
# (ej. azurerm 5.x) que rompa cosas en medio de la clase.

terraform {
  # Versión mínima de Terraform. 1.6 incorpora características que usamos
  # (validation blocks mejorados, sensitive en outputs, etc).
  required_version = ">= 1.6.0"

  required_providers {
    # azurerm: provider oficial de Azure (RGs, VMs, Storage, etc).
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # tls: genera el par de llaves SSH localmente para que no haya que
    # subir una llave manual.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # local: escribe la .pem y la .pub a disco con permisos 0600.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    # random: sufijo aleatorio para el nombre del storage account (debe ser
    # único globalmente en toda Azure).
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # http: lo usamos para auto-detectar la IP pública del operador cuando
    # `ssh_allowed_cidr = "auto"`, así el NSG queda restringido a tu IP/32.
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }

  # Backend "parcial": los valores reales (resource group, storage account,
  # container, key) los inyecta `backend.hcl`, que se genera con
  # `task backend:setup`. Esto permite tener el state remoto sin commitear
  # nombres únicos de Azure al repo.
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
