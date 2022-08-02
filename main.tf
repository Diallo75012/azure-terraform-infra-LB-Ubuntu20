# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  subscription_id = var.subscription_id
  client_id = var.client_id
  client_secret = var.client_secret
  tenant_id = var.tenant_id
}

resource "azurerm_resource_group" "vnetRG" {
  name     = "vnet-resource-group"
  location = "France Central"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.vnetRG.location
  resource_group_name = azurerm_resource_group.vnetRG.name
}

resource "azurerm_subnet" "frontend" {
  name                 = "frontend"
  resource_group_name  = azurerm_resource_group.vnetRG.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "vnetRG_security_group" {
  name                = "vnet-nsg"
  location            = azurerm_resource_group.vnetRG.location
  resource_group_name = azurerm_resource_group.vnetRG.name

  security_rule {
    name                       = "vnetSGRule"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "frontend-network-interface" {
  name                = "frontend-network-interface"
  location            = azurerm_resource_group.vnetRG.location
  resource_group_name = azurerm_resource_group.vnetRG.name

  ip_configuration {
    name                          = "frontend-ip"
    subnet_id                     = azurerm_subnet.frontend.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_subnet_network_security_group_association" "subnet_security_group_association" {
  subnet_id                 = azurerm_subnet.frontend.id
  network_security_group_id = azurerm_network_security_group.vnetRG_security_group.id
}

resource "azurerm_linux_virtual_machine" "Web" {
  name                = "Web"
  resource_group_name = azurerm_resource_group.vnetRG.name
  location            = azurerm_resource_group.vnetRG.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  depends_on          = [azurerm_resource_group.vnetRG]
  network_interface_ids = [
    azurerm_network_interface.frontend-network-interface.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}

resource "azurerm_public_ip" "LBpublicIP" {
  name                = "LBpublicIP"
  location            = azurerm_resource_group.vnetRG.location
  resource_group_name = azurerm_resource_group.vnetRG.name
  allocation_method   = "Static"
}

resource "azurerm_lb" "vnetLB" {
  name                = "vnetLB"
  //sku                 = "Standard" // have to upgrade subscription to use it otherwise it will be default basic LB which is not connecting backend load balancer to virtual machines, need to go in platform and do it manually
  location            = azurerm_resource_group.vnetRG.location
  resource_group_name = azurerm_resource_group.vnetRG.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.LBpublicIP.id
  }
}

resource "azurerm_lb_backend_address_pool" "LBbackendPool" {
  loadbalancer_id = azurerm_lb.vnetLB.id
  name            = "LBbackendPool"
}

// this is needed to connect LD backend to virtual machines through the resource group but load balancer sku needs to be of type "Standard" which is not possible with our subscription at the moment. Need to go and connect backend manually
resource "azurerm_lb_backend_address_pool_address" "LBbackendPoolAddress" {
  name                    = "LBbackendPoolAddress"
  backend_address_pool_id = azurerm_lb_backend_address_pool.LBbackendPool.id
  virtual_network_id      = azurerm_virtual_network.vnet.id
  ip_address              = "10.0.1.4"
}