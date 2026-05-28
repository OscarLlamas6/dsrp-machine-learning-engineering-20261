# ─────────────────────────────────────────────────────────────────────────────
# Outputs — lo que Terraform expone después de un `apply`.
# Inspecciónalos con `task outputs` o `terraform output <nombre>`.
# Los marcados `sensitive` requieren `-raw` para verlos:
#     terraform output -raw azure_storage_connection_string
# ─────────────────────────────────────────────────────────────────────────────

# IP pública de la VM. La usas para SSH y para validar que el NSG funciona.
output "public_ip" {
  description = "IP pública estática de la VM."
  value       = azurerm_public_ip.pip.ip_address
}

# Comando SSH listo para pegar. Lo arma con la llave que generó Terraform.
output "ssh_command" {
  description = "Comando SSH listo para usar contra la VM."
  value       = "ssh -i ${local_sensitive_file.private_key.filename} ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}

# CIDR que terminó autorizado en el NSG. Útil para verificar la auto-detección
# de IP — si esto NO coincide con tu IP real, el SSH va a colgar.
output "ssh_allowed_cidr_effective" {
  description = "CIDR autorizado en el NSG para SSH (resultado de la lógica auto/manual)."
  value       = local.effective_ssh_cidr
}

# Image ref que cloud-init va a hacer `pull`. Si no actualizaste el placeholder
# `CHANGE_ME` en tfvars, lo vas a ver aquí y la VM va a fallar el pull.
output "image_ref" {
  description = "Imagen Docker que la VM va a descargar y correr al primer boot."
  value       = var.image_ref
}

# Comando para tail de logs del trainer. `task logs` ya lo encapsula, pero
# si SSHeas a mano este es el comando.
output "tail_trainer_logs" {
  description = "Comando para seguir los logs del trainer (ejecutar en la VM)."
  value       = "sudo journalctl -u dsrp-trainer.service -f"
}

# ─── Storage de datos ──────────────────────────────────────────────────────

# Nombre del storage account creado por Terraform. Lo usas en az CLI:
#   az storage blob list --account-name <este> --container-name <abajo> --auth-mode login
output "storage_account_name" {
  description = "Nombre del storage account que contiene raw/ y models/."
  value       = azurerm_storage_account.data.name
}

# Container dentro del storage. Mismo valor que `var.azure_storage_container`,
# pero lo exponemos para que `task creds:export` no tenga que mirar la variable.
output "storage_container_name" {
  description = "Nombre del container (bucket) que usa el trainer."
  value       = azurerm_storage_container.data.name
}

# Connection string SENSITIVE. Usa `task creds:export` para vol carla al
# `.env` de la raíz; o inspecciónala con `terraform output -raw azure_storage_connection_string`.
output "azure_storage_connection_string" {
  description = <<-EOT
    Connection string del storage de datos.
    Cómo usarla:
      task creds:export                                         (escribe a ../../.env)
      terraform output -raw azure_storage_connection_string     (la imprime)
  EOT
  value       = azurerm_storage_account.data.primary_connection_string
  sensitive   = true
}

# Schedule efectivo del timer. Útil para confirmar que tfvars tomó efecto.
output "trainer_schedule" {
  description = "OnCalendar del systemd timer (vacío = solo corre al primer boot)."
  value       = var.trainer_schedule
}
