# ═══════════════════════════════════════════════════════════════════════════
# Módulo 4 — Infraestructura del trainer de Telco Churn en Azure.
#
# Lo que aprovisionamos (de arriba abajo):
#   1. Locals + tags             → nombres consistentes
#   2. Llave SSH                 → generada en tu laptop (no la subes nunca)
#   3. Storage Account de datos  → donde viven el CSV y el .pkl
#   4. Networking + NSG          → VNet/Subnet/PIP/NSG con SSH solo desde TU IP
#   5. VM Linux + cloud-init     → corre Docker y el trainer al primer boot
#
# Lee acompañado de:
#   - variables.tf  (qué puedes configurar)
#   - outputs.tf    (qué Terraform te devuelve)
#   - cloud-init.yaml (qué hace la VM al bootear)
# ═══════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# Locals: nombres y tags reusados por todos los recursos.
# Centralizarlos aquí evita tipos distintos de prefijo en distintos lugares.
# ─────────────────────────────────────────────────────────────────────────────
locals {
  # Nombre raíz que se compone para casi todo: "dsrpm4-trainer", "dsrpm4-trainer-rg", etc.
  name = "${var.prefix}-trainer"

  # Tags estándar. Azure los hereda al billing → muy útiles para filtrar costos.
  tags = {
    project = "dsrp-machine-learning-engineering"
    module  = "modulo-4-mlops-y-cloud"
    owner   = "miguel.arquez"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Auto-detección de la IP pública del operador.
# Si `var.ssh_allowed_cidr = "auto"` (default), llamamos a un servicio HTTP
# externo para descubrir desde qué IP estás corriendo Terraform y la usamos
# como ÚNICA IP autorizada para SSH al puerto 22.
#
# Si pasas un CIDR explícito (ej. "203.0.113.42/32" o "0.0.0.0/0"), ni
# siquiera hacemos la llamada (count = 0).
# ─────────────────────────────────────────────────────────────────────────────
data "http" "my_ip" {
  count = var.ssh_allowed_cidr == "auto" ? 1 : 0
  url   = "https://ifconfig.me/ip"
}

locals {
  # CIDR efectivo que termina en la regla del NSG. Hacemos `chomp` para
  # quitar el \n con el que ifconfig.me responde.
  effective_ssh_cidr = (
    var.ssh_allowed_cidr == "auto"
    ? "${chomp(data.http.my_ip[0].response_body)}/32"
    : var.ssh_allowed_cidr
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Llave SSH generada localmente.
# La privada queda en `./ssh/<name>.pem` (gitignored, permisos 0600);
# la pública se inyecta en la VM via `admin_ssh_key`.
# ─────────────────────────────────────────────────────────────────────────────

# Par RSA-4096. Cada `terraform apply` que NO la encuentre en el state genera
# una nueva; por eso es importante no borrar el state o las llaves a mano.
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Escribe la llave PRIVADA a disco. `local_sensitive_file` evita que el
# contenido aparezca en `terraform plan`. Permisos 0600 = solo el dueño puede leer.
resource "local_sensitive_file" "private_key" {
  filename        = "${path.module}/ssh/${local.name}.pem"
  content         = tls_private_key.ssh.private_key_pem
  file_permission = "0600"
}

# Escribe la llave PÚBLICA al lado, por si quieres copiarla a otro lado.
resource "local_file" "public_key" {
  filename        = "${path.module}/ssh/${local.name}.pub"
  content         = tls_private_key.ssh.public_key_openssh
  file_permission = "0644"
}

# ─────────────────────────────────────────────────────────────────────────────
# Storage Account de DATOS (no es el del state, que vive en otro RG aparte).
# Aquí caen `raw/telco_churn.csv` (input) y `models/telco_churn_logreg.pkl`
# (output del trainer). El nombre tiene que ser único globalmente en Azure,
# por eso le pegamos un sufijo aleatorio.
# ─────────────────────────────────────────────────────────────────────────────

# Sufijo aleatorio: 4 bytes = 8 caracteres hex. Persistente en el state, así
# que no cambia entre applies.
resource "random_id" "sa_suffix" {
  byte_length = 4
}

resource "azurerm_storage_account" "data" {
  # Nombre: prefix + "data" + sufijo. Azure exige 3-24 chars, solo lowercase
  # y dígitos. Con prefix=dsrpm4 → "dsrpm4dataXXXXXXXX" (18 chars). ✓
  name                = "${var.prefix}data${random_id.sa_suffix.hex}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  # Tier Standard + LRS = la opción más barata y suficiente para el módulo.
  # Para producción de verdad usarías GRS o RA-GRS para tener réplica geográfica.
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Account kind StorageV2 = el general-purpose moderno (blob, file, queue, table).
  # No uses BlockBlobStorage aquí — es más caro y solo agrega features premium.
  account_kind = "StorageV2"

  # Defensa básica: TLS 1.2 mínimo + bloquear acceso anónimo a containers.
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = true  # accesible desde internet (necesitamos eso)
  allow_nested_items_to_be_public = false # pero ningún blob individual puede ser público

  tags = local.tags
}

# Container (= bucket en S3) dentro del storage account.
# Privado por default → todo el mundo necesita la connection string para leer.
resource "azurerm_storage_container" "data" {
  name                  = var.azure_storage_container
  storage_account_id    = azurerm_storage_account.data.id
  container_access_type = "private"
}

# ─────────────────────────────────────────────────────────────────────────────
# Networking: RG + VNet + Subnet + IP pública estática + NSG + NIC.
# Estructura clásica de "una VM expuesta al internet":
#
#   internet ──→ Public IP ──→ NIC ──→ Subnet ──→ VNet
#                                  └── NSG (firewall)
# ─────────────────────────────────────────────────────────────────────────────

# Resource Group: contenedor lógico de TODOS los recursos del módulo.
# Borrar este RG borra todo (eso hace `task destroy`).
resource "azurerm_resource_group" "rg" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = local.tags
}

# Red virtual privada. 10.10.0.0/16 nos da espacio de sobra; en este módulo
# solo usamos una subnet pequeñita.
resource "azurerm_virtual_network" "vnet" {
  name                = "${local.name}-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

# Subnet única (10.10.1.0/24 = 256 IPs, Azure reserva las primeras 5).
resource "azurerm_subnet" "subnet" {
  name                 = "${local.name}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

# IP pública estática (no cambia si reinicias la VM). SKU Standard es el
# moderno y obligatorio para Availability Zones.
resource "azurerm_public_ip" "pip" {
  name                = "${local.name}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# Network Security Group = firewall a nivel de subnet/NIC.
# Solo dejamos pasar SSH (puerto 22) y SOLO desde el CIDR autorizado.
# Todo lo demás queda implícitamente bloqueado por las reglas default de Azure.
resource "azurerm_network_security_group" "nsg" {
  name                = "${local.name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  security_rule {
    name      = "allow-ssh"
    priority  = 100 # menor = más prioridad; 100 es el primer slot disponible
    direction = "Inbound"
    access    = "Allow"
    protocol  = "Tcp"

    source_port_range      = "*" # cualquier puerto cliente
    destination_port_range = "22"

    # `local.effective_ssh_cidr` viene de la lógica de auto-IP arriba.
    # Si `ssh_allowed_cidr = "auto"` → tu IP/32. Si lo fijaste a mano → ese valor.
    source_address_prefix      = local.effective_ssh_cidr
    destination_address_prefix = "*"
  }
}

# NIC virtual con IP dinámica interna + asociada a la IP pública estática.
resource "azurerm_network_interface" "nic" {
  name                = "${local.name}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# Pega el NSG a la NIC. Sin esto, las reglas del NSG no aplican.
resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ─────────────────────────────────────────────────────────────────────────────
# Máquina Virtual Linux (Ubuntu 24.04 LTS).
# Al primer boot ejecuta `cloud-init.yaml`, que:
#   - instala Docker
#   - opcionalmente hace `docker login ghcr.io` (si la imagen es privada)
#   - corre `docker pull` + `docker run` del trainer
#   - registra `dsrp-trainer.service` (oneshot) y `dsrp-trainer.timer` (cron)
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "vm" {
  name                            = local.name
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  network_interface_ids           = [azurerm_network_interface.nic.id]
  disable_password_authentication = true # password auth OFF → solo SSH key
  tags                            = local.tags

  # La pública generada arriba se sube acá como llave autorizada.
  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  # Disco OS — 30 GB es mucho para una Ubuntu mínima, pero deja espacio
  # cómodo para la imagen Docker + capas + logs.
  os_disk {
    name                 = "${local.name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  # Imagen base: Canonical Ubuntu 24.04 LTS (Noble). LTS = soporte largo,
  # lo que nos importa para que cloud-init y apt funcionen como esperamos.
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # cloud-init: el "primer boot script". Se renderiza con `templatefile()`
  # inyectando la connection string del storage (computada por TF), el image_ref
  # de GHCR y opcionalmente el schedule del timer.
  #
  # OJO: Azure solo ejecuta custom_data UNA vez en el primer boot. Si cambias
  # algo aquí después, hay que recrear la VM:
  #   terraform taint azurerm_linux_virtual_machine.vm && task apply
  custom_data = base64encode(
    templatefile("${path.module}/cloud-init.yaml", {
      conn_str   = azurerm_storage_account.data.primary_connection_string
      container  = var.azure_storage_container
      image_ref  = var.image_ref
      ghcr_user  = var.ghcr_username
      ghcr_token = var.ghcr_token
      admin_user = var.admin_username
      schedule   = var.trainer_schedule
    })
  )
}
