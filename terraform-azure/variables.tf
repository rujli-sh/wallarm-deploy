
variable "resource_group_name" {
  description = "Name of the resource group container for all resources"
}

variable "resource_group_location" {
  description = "Resource group location"
}

variable "resource_group_location2" {
  description = "Resource group location"
}

variable "vm_sku" {
  description = "Size of VMs in the VM Scale Set."
  default     = "Standard_A1"
}

variable "ubuntu_os_version" {
  description = "The Ubuntu version for the VM. This will pick a fully patched image of this given Ubuntu version. Allowed values are: 14.04.4-LTS, 16.04.0-LTS."
  default     = "16.04.0-LTS"
}
# "maxLength": 61
variable "vmss_name" {
  description = "String used as a base for naming resources. Must be 3-61 characters in length and globally unique across Azure. A hash is prepended to this string for some resources, and resource-specific information is appended."
}

# "maxValue": 100
variable "instance_count" {
  description = "Number of VM instances (100 or less)."
}

variable "admin_username" {
  description = "Admin username on all VMs."
}

variable "admin_password" {
  description = "Admin password for all VMs"
}

variable "admin_sshkey" {
  type        = string
  description = "SSH key for authentication to the Virtual Machines"
  default     = "~/.ssh/id_rsa.pub"
}

variable "deploy_user" {
  type        = string
  description = "Wallarm username with Deploy role"
}

variable "deploy_password" {
  type        = string
  description = "The password of Wallarm user with Deploy role"
}

variable "protected_domain" {
  type        = string
  description = "The name of domain to be protected by the WAF cluster"
}

variable "protected_origin" {
  type        = string
  description = "The name or IP address of origin server"
}

variable "wallarm_cloud" {
  type        = string
  description = "The code name of Wallarm Cloud to use - us1 or eu"
  default     = "us1"
}

