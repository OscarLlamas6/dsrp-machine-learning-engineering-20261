variable "subscription_id" {
  description = "Azure subscription ID where everything is created."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "prefix" {
  description = "Prefix for all resources (≤ 10 chars, lowercase, no symbols)."
  type        = string
  default     = "dsrpm4"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,9}$", var.prefix))
    error_message = "prefix must be 3–10 chars, lowercase letters/digits, start with a letter."
  }
}

variable "vm_size" {
  description = "Azure VM size. B1s is roughly 'micro'; B1ls is the cheapest."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "Linux user on the VM."
  type        = string
  default     = "azureuser"
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH. Restrict to your IP in production!"
  type        = string
  default     = "0.0.0.0/0"
}

variable "image_ref" {
  description = "Docker image to pull and run on boot. Override with your GHCR image."
  type        = string
  default     = "ghcr.io/CHANGE_ME/dsrp-modulo4-trainer:latest"
}

variable "azure_storage_connection_string" {
  description = "Connection string injected into the container so it can read/write blobs."
  type        = string
  sensitive   = true
}

variable "azure_storage_container" {
  description = "Blob container the training image will use."
  type        = string
  default     = "dsrp-modulo4"
}

variable "ghcr_username" {
  description = "GitHub username to docker login against ghcr.io (only needed if the image is private)."
  type        = string
  default     = ""
}

variable "ghcr_token" {
  description = "GitHub PAT with read:packages, used to pull a private GHCR image. Leave empty for public images."
  type        = string
  default     = ""
  sensitive   = true
}
