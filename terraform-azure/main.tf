
#
# The Ubuntu version for the VM. This will pick a fully patched image of this given Ubuntu version.
#
variable "ubuntu_os_version_map" {
  type = map

  default = {
    "16.04.0-LTS" = "16.04.0-LTS"
    "18.04.0-LTS" = "18.04-LTS"
  }
}

variable "config" {
  type = map

  default = {
    "address_prefix"       = "10.0.0.0/16"
    "subnet_prefix"        = "10.0.0.0/24"
    "nat_start_port"       = "50000"
    "nat_end_port"         = "50119"
    "nat_backend_port"     = "22"
    "os_type_publisher"    = "Canonical"
    "os_type_offer"        = "UbuntuServer"
    "os_type_version"      = "latest"
    "storage_account_type" = "Standard_LRS"
  }
}

# Unique name for the storage account
resource "random_id" "storage_account_name" {
  keepers = {
    # Generate a new id each time a new resource group is defined
    resource_group = var.resource_group_name
  }

  byte_length = 8
}

# Need to add resource group for Terraform
resource "azurerm_resource_group" "resource_group" {
  name     = var.resource_group_name
  location = var.resource_group_location

  tags = {
    Source = "Azure Quickstarts for Terraform"
  }
}

# Need a storage account until managed disks supported by terraform provider
resource "azurerm_storage_account" "storage_account1" {
  name                = random_id.storage_account_name.hex
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = var.resource_group_location
  #  account_type        = "${var.config["storage_account_type"]}"
  account_replication_type = "GRS"
  account_tier             = "Standard"

  tags = {
    Source = "Azure Quickstarts for Terraform"
  }
}

# Need a storage container until managed disks supported by terraform provider
resource "azurerm_storage_container" "storage_container1" {
  name = "vhds"
  #  resource_group_name   = azurerm_resource_group.resource_group.name
  storage_account_name  = azurerm_storage_account.storage_account1.name
  container_access_type = "private"
}

resource "azurerm_public_ip" "public_ip1" {
  name                = "${var.vmss_name}pip"
  location            = var.resource_group_location
  resource_group_name = azurerm_resource_group.resource_group.name
  # public_ip_address_allocation = "static"
  allocation_method = "Static"
  domain_name_label = lower(var.vmss_name)

  tags = {
    Source = "Azure Quickstarts for Terraform"
  }
}

resource "azurerm_virtual_network" "virtual_network1" {
  name                = "${var.vmss_name}vnet"
  address_space       = [var.config["address_prefix"]]
  location            = var.resource_group_location
  resource_group_name = azurerm_resource_group.resource_group.name

  tags = {
    Source = "Azure Quickstarts for Terraform"
  }
}

resource "azurerm_subnet" "subnet1" {
  name                 = "${var.vmss_name}subnet"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network1.name
  address_prefixes     = [var.config["subnet_prefix"]]
}

resource "azurerm_virtual_machine_scale_set" "vm_scale_set1" {
  name                = var.vmss_name
  location            = var.resource_group_location
  resource_group_name = azurerm_resource_group.resource_group.name
  upgrade_policy_mode = "Manual"
  overprovision       = "true"

  sku {
    name     = var.vm_sku
    tier     = "Standard"
    capacity = var.instance_count
  }

  network_profile {
    name    = "${var.vmss_name}nic"
    primary = true

    ip_configuration {
      name                                   = "${var.vmss_name}ipconfig"
      subnet_id                              = azurerm_subnet.subnet1.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.backend_address_pool_http.id]
      primary                                = true
    }
  }

  storage_profile_os_disk {
    name           = "osdisk1"
    caching        = "ReadWrite"
    create_option  = "FromImage"
    vhd_containers = ["${azurerm_storage_account.storage_account1.primary_blob_endpoint}${azurerm_storage_container.storage_container1.name}"]
  }

  storage_profile_image_reference {
    publisher = var.config["os_type_publisher"]
    offer     = var.config["os_type_offer"]
    sku       = lookup(var.ubuntu_os_version_map, var.ubuntu_os_version)
    version   = var.config["os_type_version"]
  }

  os_profile {
    computer_name_prefix = var.vmss_name
    admin_username       = var.admin_username
    admin_password       = var.admin_password
    custom_data          = templatefile("script.sh.tmpl", { deploy_user = var.deploy_user, deploy_password = var.deploy_password, wallarm_cloud = var.wallarm_cloud, protected_domain = var.protected_domain, protected_origin = var.protected_origin })
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"
      key_data = file(var.admin_sshkey)
    }
  }

  tags = {
    Source = "Azure Quickstarts for Terraform"
  }
}

resource "azurerm_lb_probe" "http" {
  resource_group_name = azurerm_resource_group.resource_group.name
  loadbalancer_id     = azurerm_lb.http.id
  name                = "http-probe"
  protocol            = "Http"
  request_path        = "/"
  port                = 80
}

resource "azurerm_public_ip" "http" {
  name                = "HttpLoadBalancer"
  location            = var.resource_group_location
  resource_group_name = azurerm_resource_group.resource_group.name
  allocation_method   = "Static"
}

resource "azurerm_lb" "http" {
  name                = "HttpLoadBalancer"
  location            = var.resource_group_location
  resource_group_name = azurerm_resource_group.resource_group.name

  frontend_ip_configuration {
    name                 = "loadBalancerFrontEnd"
    public_ip_address_id = azurerm_public_ip.http.id
  }
}

resource "azurerm_lb_rule" "http" {
  resource_group_name            = azurerm_resource_group.resource_group.name
  loadbalancer_id                = azurerm_lb.http.id
  name                           = "HttpLBRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "loadBalancerFrontEnd"
  backend_address_pool_id        = azurerm_lb_backend_address_pool.backend_address_pool_http.id
  probe_id                       = azurerm_lb_probe.http.id
}

resource "azurerm_lb_backend_address_pool" "backend_address_pool_http" {
  resource_group_name = azurerm_resource_group.resource_group.name
  loadbalancer_id     = azurerm_lb.http.id
  name                = "${var.vmss_name}bepoolhttp"
}

output "http_lb_ip_address" {
  value = azurerm_public_ip.http.ip_address
}
