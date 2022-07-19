terraform {
  required_version = ">=0.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "instance_id" {
  type    = string
  default = "mtk"
}

resource "azurerm_resource_group" "rg" {
  name      = "fabmedical-rg-${var.instance_id}"
  location  = "eastus"
}

# Create virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "fabmedical-vnet"
  address_space       = ["10.0.0.0/26"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create subnet
resource "azurerm_subnet" "snet" {
  name                 = "fabmedical-snet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/27"]
}

# Create public IPs
resource "azurerm_public_ip" "pip" {
  name                = "fabmedical-pip"
  location            = azurerm_resource_group.rg.location
  domain_name_label   = "fabmedical-pipdnl"
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "nsg" {
  name                = "fabmedical-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "WebApp"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create network interface
resource "azurerm_network_interface" "nnic" {
  name                = "fabmedical-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "fabmedical-nicconf"
    subnet_id                     = azurerm_subnet.snet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "nsgass" {
  network_interface_id      = azurerm_network_interface.nnic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "fabmedical-vm"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nnic.id]
  size                  = "Standard_B1s"

  os_disk {
    name                 = "fabmedical-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Debian"
    offer     = "debian-11"
    sku       = "11"
    version   = "latest"
  }

  computer_name                   = "fabvm"
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  connection {
    type        = "ssh"
    user        = "azureuser"
    private_key = file("~/.ssh/id_rsa")
    host        = azurerm_public_ip.pip.fqdn
  }

  provisioner "remote-exec" {
    scripts = [
      "temp_vm_init.sh"
    ]
  }
}

data "azurerm_public_ip" "pip" {
  name                = azurerm_public_ip.pip.name
  resource_group_name = azurerm_resource_group.rg.name
  #depends_on          = [time_sleep.wait_1_second]
}
output "assigned_username" {
  value = azurerm_linux_virtual_machine.vm.admin_username
}
output "assigned_pip" {
  #value = azurerm_public_ip.pip.ip_address
  value = data.azurerm_public_ip.pip.ip_address
}
output "assigned_fqdn" {
  value = azurerm_public_ip.pip.fqdn
}
