output "public_ip" {
  description = "Public IP of the VM."
  value       = azurerm_public_ip.pip.ip_address
}

output "ssh_command" {
  description = "Ready-to-paste SSH command."
  value       = "ssh -i ${local_sensitive_file.private_key.filename} ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}

output "image_ref" {
  description = "Docker image the VM will pull and run on boot."
  value       = var.image_ref
}

output "tail_trainer_logs" {
  description = "Run this after SSHing in to watch the trainer's first run."
  value       = "sudo journalctl -u dsrp-trainer.service -f"
}
