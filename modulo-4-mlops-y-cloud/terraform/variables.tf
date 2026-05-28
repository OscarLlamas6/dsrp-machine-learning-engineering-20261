# ─────────────────────────────────────────────────────────────────────────────
# Variables de entrada del módulo 4.
# Todo lo que pongas aquí va a vivir en `dsrp-values.tfvars` (gitignored).
# Cada variable trae un comentario explicando QUÉ es y CUÁNDO cambiarla.
# ─────────────────────────────────────────────────────────────────────────────

variable "subscription_id" {
  description = <<-EOT
    ID de la suscripción de Azure donde se crea TODA la infra del módulo
    (RG, VM, storage, networking). Obténlo con:
        az account show --query id -o tsv
  EOT
  type        = string
}

variable "location" {
  description = <<-EOT
    Región de Azure. Default: centralus.

    Por qué NO eastus en este curso (lección aprendida):
      La suscripción dsrp-mle-2026 NO tiene la familia BS (B2s/B2ms)
      ofrecida en eastus, eastus2, ni westus2 — Azure no las expone para
      esta sub. Quedan disponibles las familias DSv4 / DASv4 / DDSv4 en
      centralus y westus3 (cuota = 10 vCPU cada una, suficiente para una
      VM de 2 vCPU). Por eso defaulteamos a centralus + Standard_D2as_v4.

    Cómo confirmar antes de cambiar:
      task vm:check-skus           (verifica SKU+región contra tu sub)
  EOT
  type        = string
  default     = "centralus"
}

variable "prefix" {
  description = <<-EOT
    Prefijo que se antepone a todos los recursos del módulo. Debe ser corto
    porque el nombre del storage account es `<prefix>data<hex8>` y Azure
    limita los storage accounts a 24 caracteres.

    Reglas: 3-10 caracteres, solo minúsculas y dígitos, empezar con letra.
  EOT
  type        = string
  default     = "dsrpm4"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,9}$", var.prefix))
    error_message = "prefix debe tener 3-10 caracteres, solo letras minúsculas y dígitos, empezando con letra."
  }
}

variable "vm_size" {
  description = <<-EOT
    Tamaño de la VM. Default Standard_D2as_v4 (2 vCPU / 8 GiB / AMD EPYC GP).

    Elegimos D2as_v4 (no B2s) porque:
      - La familia BS no está disponible en esta suscripción en ninguna
        región revisada (eastus / eastus2 / westus2 / westus3 / centralus).
      - DASv4 sí está disponible en centralus y westus3, con quota=10 vCPU
        (suficiente para esta VM de 2 vCPU).
      - 8 GiB RAM es margen cómodo para `docker pull` + sklearn fit, sin
        riesgo de OOM como tenía B2s.

    Alternativas confirmadas en centralus/westus3 si DASv4 estuviera lleno:
      - Standard_D2s_v4   (Intel, igual specs)
      - Standard_D2ds_v4  (Intel + local SSD)

    NO uses B-series sin verificar primero con `task vm:check-skus`.
  EOT
  type        = string
  default     = "Standard_D2as_v4"
}

variable "admin_username" {
  description = "Usuario Linux que se crea en la VM. Lo usas para SSH."
  type        = string
  default     = "azureuser"
}

variable "ssh_allowed_cidr" {
  description = <<-EOT
    CIDR autorizado para SSH (puerto 22) en el NSG.

    Tres formas de usarlo:
      - "auto"             → Terraform consulta https://ifconfig.me/ip y
                              te abre SOLO tu IP/32. Es el default y lo más
                              seguro. Si tu IP cambia, vuelve a hacer
                              `task apply` y se actualiza el NSG.
      - "203.0.113.42/32"  → fíjala manualmente (útil en CI o si tu IP
                              tarda en propagarse).
      - "0.0.0.0/0"        → abre SSH al mundo. NUNCA en producción.
  EOT
  type        = string
  default     = "auto"
}

variable "image_ref" {
  description = <<-EOT
    Imagen Docker que la VM va a hacer `pull` y correr al primer boot.
    Normalmente:  ghcr.io/<tu-usuario>/dsrp-modulo4-trainer:latest
    Esta imagen la construye la GitHub Action
    `.github/workflows/build-modulo4-image.yml`.
  EOT
  type        = string
  default     = "ghcr.io/CHANGE_ME/dsrp-modulo4-trainer:latest"
}

variable "azure_storage_container" {
  description = <<-EOT
    Nombre del container (bucket) dentro del storage account de datos.
    Es donde el trainer lee `raw/telco_churn.csv` y deja
    `models/telco_churn_logreg.pkl`. Mismo nombre que usa el notebook 02.
  EOT
  type        = string
  default     = "dsrp-modulo4"
}

variable "ghcr_username" {
  description = <<-EOT
    Usuario de GitHub para `docker login ghcr.io`. Solo necesario si la
    imagen del trainer es PRIVADA. Si es pública, déjalo vacío.
  EOT
  type        = string
  default     = ""
}

variable "ghcr_token" {
  description = <<-EOT
    Personal Access Token de GitHub con scope `read:packages`.
    Solo necesario para imágenes privadas en GHCR. Marcado como `sensitive`
    para que Terraform NO lo imprima en plan/apply.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "trainer_schedule" {
  description = <<-EOT
    Expresión `OnCalendar` de systemd para re-ejecutar el trainer en
    intervalo (ver `man systemd.time`).

    Ejemplos:
      "hourly"                 cada hora en punto
      "daily"                  cada día a las 00:00 UTC
      "*-*-* 03:00:00"         todos los días a las 03:00 UTC
      "Mon..Fri 08:00:00"      lunes a viernes 08:00 UTC
      "*:0/15"                 cada 15 minutos

    Si lo dejas vacío (default), el trainer se ejecuta SOLO en el primer
    boot. El timer queda instalado pero deshabilitado — puedes encenderlo
    después con `task trainer:schedule:on`.
  EOT
  type        = string
  default     = ""
}
