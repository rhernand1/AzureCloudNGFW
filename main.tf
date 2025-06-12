# main.tf for github.com/rhernand1/AzureCloudNGFW (this is the actual NGFW module)

# --- Provider Configuration ---
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.117.0" # Make sure this is updated!
    }
  }
}

provider "azurerm" {
  features {}
}

# --- Input Variables for THIS Module (AzureCloudNGFW) ---
variable "resource_group_name" {
  description = "The name of the Azure Resource Group for the Cloud NGFW."
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be deployed."
  type        = string
}

variable "firewall_name" {
  description = "The name of the Palo Alto Networks Cloud NGFW instance."
  type        = string
}

variable "vnet_name" {
  description = "The name of the Virtual Network (VNet) for the NGFW interfaces."
  type        = string
}

variable "vnet_address_space" {
  description = "The address space (CIDR) for the VNet."
  type        = list(string)
}

variable "untrusted_subnet_name" {
  description = "The name of the untrusted subnet for the NGFW interface."
  type        = string
}

variable "untrusted_subnet_prefix" {
  description = "The address prefix (CIDR) for the untrusted subnet."
  type        = string
}

variable "trusted_subnet_name" {
  description = "The name of the trusted subnet for the NGFW interface."
  type        = string
}

variable "trusted_subnet_prefix" {
  description = "The address prefix (CIDR) for the trusted subnet."
  type        = string
}

variable "management_subnet_name" {
  description = "The name of the management subnet for the NGFW interface (optional)."
  type        = string
}

variable "management_subnet_prefix" {
  description = "The address prefix (CIDR) for the management subnet (optional)."
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to all deployed resources."
  type        = map(string)
}

# --- Azure Resource Group ---
resource "azurerm_resource_group" "ngfw_rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# --- Virtual Network (VNet) ---
resource "azurerm_virtual_network" "ngfw_vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.ngfw_rg.location
  resource_group_name = azurerm_resource_group.ngfw_rg.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# --- Subnets for NGFW Interfaces ---
resource "azurerm_subnet" "untrusted_subnet" {
  name                 = var.untrusted_subnet_name
  resource_group_name  = azurerm_resource_group.ngfw_rg.name
  virtual_network_name = azurerm_virtual_network.ngfw_vnet.name
  address_prefixes     = [var.untrusted_subnet_prefix]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.KeyVault"]
}

resource "azurerm_subnet" "trusted_subnet" {
  name                 = var.trusted_subnet_name
  resource_group_name  = azurerm_resource_group.ngfw_rg.name
  virtual_network_name = azurerm_virtual_network.ngfw_vnet.name
  address_prefixes     = [var.trusted_subnet_prefix]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.KeyVault"]
}

resource "azurerm_subnet" "management_subnet" {
  name                 = var.management_subnet_name
  resource_group_name  = azurerm_resource_group.ngfw_rg.name
  virtual_network_name = azurerm_virtual_network.ngfw_vnet.name
  address_prefixes     = [var.management_subnet_prefix]
}

# --- Public IP Addresses for NGFW Frontend ---
resource "azurerm_public_ip" "ngfw_public_ip_ingress" {
  name                = "${var.firewall_name}-pip-ingress"
  location            = azurerm_resource_group.ngfw_rg.location
  resource_group_name = azurerm_resource_group.ngfw_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_public_ip" "ngfw_public_ip_egress" {
  name                = "${var.firewall_name}-pip-egress"
  location            = azurerm_resource_group.ngfw_rg.location
  resource_group_name = azurerm_resource_group.ngfw_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# --- Palo Alto Networks Cloud NGFW Resource ---
resource "azurerm_palo_alto_next_generation_firewall_local_rulestack" "ngfw" {
  name                = var.firewall_name
  location            = azurerm_resource_group.ngfw_rg.location
  resource_group_name = azurerm_resource_group.ngfw_rg.name
  tags                = var.tags

  network_profile {
    public_ip_address_ids = [
      azurerm_public_ip.ngfw_public_ip_ingress.id,
      azurerm_public_ip.ngfw_public_ip_egress.id,
    ]

    vnet_configuration {
      virtual_network_id  = azurerm_virtual_network.ngfw_vnet.id
      trusted_subnet_id   = azurerm_subnet.trusted_subnet.id
      untrusted_subnet_id = azurerm_subnet.untrusted_subnet.id
    }
  }

  local_rulestack {
    name       = "${var.firewall_name}-rulestack"
    location   = azurerm_resource_group.ngfw_rg.location
    min_engine_version = "9.0.0"

    security_services {
      anti_spyware_profile_name = "default"
      anti_virus_profile_name   = "default"
      url_filtering_profile_name = "default"
      file_blocking_profile_name = "default"
      dns_security_profile_name = "default"
    }
  }
}

# --- Outputs from THIS Module (AzureCloudNGFW) ---
output "cloud_ngfw_name" {
  description = "The name of the deployed Cloud NGFW instance."
  value       = azurerm_palo_alto_next_generation_firewall_local_rulestack.ngfw.name
}

output "cloud_ngfw_public_ip_ingress" {
  description = "The Public IP address for ingress traffic to the Cloud NGFW."
  value       = azurerm_public_ip.ngfw_public_ip_ingress.ip_address
}

output "cloud_ngfw_public_ip_egress" {
  description = "The Public IP address for egress traffic from the Cloud NGFW."
  value       = azurerm_public_ip.ngfw_public_ip_egress.ip_address
}

output "ngfw_vnet_id" {
  description = "The ID of the Virtual Network where the NGFW interfaces are located."
  value       = azurerm_virtual_network.ngfw_vnet.id
}

output "ngfw_untrusted_subnet_id" {
  description = "The ID of the untrusted subnet connected to the NGFW."
  value       = azurerm_subnet.untrusted_subnet.id
}

output "ngfw_trusted_subnet_id" {
  description = "The ID of the trusted subnet connected to the NGFW."
  value       = azurerm_subnet.trusted_subnet.id
}
