# This OpenTofu script deploys a Palo Alto Networks Cloud Next-Generation Firewall (NGFW) in Azure.
# It includes the creation of:
# - A dedicated Azure Resource Group.
# - A Virtual Network (VNet) with specific subnets for the NGFW's interfaces.
# - Public IP addresses for the NGFW's frontend.
# - The Cloud NGFW resource itself, configured to attach to the created network components.

# --- Provider Configuration ---
# Specifies the required AzureRM provider and its version.
# OpenTofu will download this provider during 'opentofu init'.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0" # It's best practice to pin to a specific major version
                         # Check the Terraform Registry for the latest compatible version.
    }
  }
}

# Configures the AzureRM provider.
# The 'features' block is mandatory for the AzureRM provider.
provider "azurerm" {
  features {}
}

# --- Input Variables ---
# These variables allow for customization of the deployment.

variable "resource_group_name" {
  description = "The name of the Azure Resource Group for the Cloud NGFW."
  type        = string
  default     = "RHTESTING" # As requested by the user
}

variable "location" {
  description = "The Azure region where resources will be deployed."
  type        = string
  default     = "East US 2" # Example region, choose one near you
}

variable "firewall_name" {
  description = "The name of the Palo Alto Networks Cloud NGFW instance."
  type        = string
  default     = "cngfwrh" # As requested by the user
}

variable "vnet_name" {
  description = "The name of the Virtual Network (VNet) for the NGFW interfaces."
  type        = string
  default     = "ngfw-vnet-01"
}

variable "vnet_address_space" {
  description = "The address space (CIDR) for the VNet."
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "untrusted_subnet_name" {
  description = "The name of the untrusted subnet for the NGFW interface."
  type        = string
  default     = "untrusted-subnet"
}

variable "untrusted_subnet_prefix" {
  description = "The address prefix (CIDR) for the untrusted subnet."
  type        = string
  default     = "10.10.0.0/28"
}

variable "trusted_subnet_name" {
  description = "The name of the trusted subnet for the NGFW interface."
  type        = string
  default     = "trusted-subnet"
}

variable "trusted_subnet_prefix" {
  description = "The address prefix (CIDR) for the trusted subnet."
  type        = string
  default     = "10.10.0.16/28"
}

variable "management_subnet_name" {
  description = "The name of the management subnet for the NGFW interface (optional)."
  type        = string
  default     = "management-subnet"
}

variable "management_subnet_prefix" {
  description = "The address prefix (CIDR) for the management subnet (optional)."
  type        = string
  default     = "10.10.0.32/28"
}

variable "tags" {
  description = "A map of tags to apply to all deployed resources."
  type        = map(string)
  default = {
    Environment = "Dev"
    Project     = "CloudNGFWDemo"
    ManagedBy   = "OpenTofu"
  }
}

# --- Azure Resource Group ---
# Creates a new Azure Resource Group to contain all the NGFW resources.
resource "azurerm_resource_group" "ngfw_rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# --- Virtual Network (VNet) ---
# Creates the Virtual Network where the NGFW's interfaces will reside.
resource "azurerm_virtual_network" "ngfw_vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.ngfw_rg.location
  resource_group_name = azurerm_resource_group.ngfw_rg.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# --- Untrusted Subnet for NGFW Interface ---
# This subnet is used for traffic entering the NGFW from untrusted sources (e.g., Internet).
resource "azurerm_subnet" "untrusted_subnet" {
  name                 = var.untrusted_subnet_name
  resource_group_name  = azurerm_resource_group.ngfw_rg.name
  virtual_network_name = azurerm_virtual_network.ngfw_vnet.name
  address_prefixes     = [var.untrusted_subnet_prefix]
  # Service endpoints are often enabled for security services
  service_endpoints    = ["Microsoft.Storage", "Microsoft.KeyVault"]
}

# --- Trusted Subnet for NGFW Interface ---
# This subnet is used for traffic exiting the NGFW to trusted destinations (e.g., internal applications).
resource "azurerm_subnet" "trusted_subnet" {
  name                 = var.trusted_subnet_name
  resource_group_name  = azurerm_resource_group.ngfw_rg.name
  virtual_network_name = azurerm_virtual_network.ngfw_vnet.name
  address_prefixes     = [var.trusted_subnet_prefix]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.KeyVault"]
}

# --- Management Subnet for NGFW Interface (Optional but Recommended) ---
# This subnet can be used for dedicated management access to the NGFW.
resource "azurerm_subnet" "management_subnet" {
  name                 = var.management_subnet_name
  resource_group_name  = azurerm_resource_group.ngfw_rg.name
  virtual_network_name = azurerm_virtual_network.ngfw_vnet.name
  address_prefixes     = [var.management_subnet_prefix]
}

# --- Public IP Addresses for NGFW Frontend ---
# The Cloud NGFW requires public IP addresses for its external facing interfaces (e.g., ingress/egress NAT).
# We'll create two as a common scenario, one for ingress and one for egress.
resource "azurerm_public_ip" "ngfw_public_ip_ingress" {
  name                = "${var.firewall_name}-pip-ingress"
  location            = azurerm_resource_group.ngfw_rg.location
  resource_group_name = azurerm_resource_group.ngfw_rg.name
  allocation_method   = "Static"
  sku                 = "Standard" # Standard SKU is generally recommended for production
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
# This is the main resource that provisions the Cloud NGFW service.
# It defines the NGFW's name, location, and its network configuration.
resource "azurerm_palo_alto_next_generation_firewall_virtual_network_appliance" "ngfw" {
  name                = var.firewall_name
  location            = azurerm_resource_group.ngfw_rg.location
  resource_group_name = azurerm_resource_group.ngfw_rg.name
  tags                = var.tags

  # Network profile configuration for the NGFW interfaces
  network_profile {
    # Public IP addresses assigned to the NGFW for external connectivity.
    public_ip_address_ids = [
      azurerm_public_ip.ngfw_public_ip_ingress.id,
      azurerm_public_ip.ngfw_public_ip_egress.id,
    ]

    # Virtual Network configuration for the NGFW's internal interfaces.
    vnet_configuration {
      virtual_network_id  = azurerm_virtual_network.ngfw_vnet.id
      trusted_subnet_id   = azurerm_subnet.trusted_subnet.id
      untrusted_subnet_id = azurerm_subnet.untrusted_subnet.id
      # Optional: if you have a separate management subnet, specify it here.
      # ip_of_trusted_subnet_for_free_mode = "" # Usually not needed for standard deployments
    }

    # Optional: Management network profile if distinct from data interfaces.
    # The Cloud NGFW service might have specific requirements for management.
    # Refer to Palo Alto's documentation for exact requirements.
    # For a simple deployment, if management access uses the same VNet, it might
    # not need a separate block, or the NGFW resource might implicitly handle it.
    # However, if you need a dedicated management interface (e.g., for Panorama),
    # it would typically be configured within the NGFW resource or its associated rulestack.
    # The resource 'azurerm_palo_alto_next_generation_firewall_virtual_network_appliance'
    # generally does not have a separate `management_network_profile` block for VNet attachment,
    # as its management is often cloud-managed or integrated via a rulestack.
    # We include the management subnet as a general network best practice for future use
    # or specific Panorama deployment models.
  }

  # --- Local Rulestack Configuration (Mandatory for CloudManaged NGFW) ---
  # The Cloud NGFW needs a rulestack to define its security policies.
  # This example uses a local rulestack (CloudManaged by Azure).
  # If you were using Panorama, you would use a different resource type
  # like `azurerm_palo_alto_next_generation_firewall_virtual_hub_panorama`
  # or configure the Panorama integration within the `local_rulestack` block.
  local_rulestack {
    name       = "${var.firewall_name}-rulestack"
    location   = azurerm_resource_group.ngfw_rg.location
    min_engine_version = "9.0.0" # Example min engine version, adjust as needed
    security_services {
      anti_spyware_profile_name = "default"
      anti_virus_profile_name   = "default"
      url_filtering_profile_name = "default"
      file_blocking_profile_name = "default"
      dns_security_profile_name = "default"
      # Add other security services as required
    }
  }

  # Add other mandatory or optional configuration blocks based on your needs
  # and the specific features of the Cloud NGFW you want to enable.
  # e.g., `destination_nat`, `egress_nat`, `dns_settings`, `diagnostics`
}

# --- Outputs ---
# Provides useful information about the deployed resources after apply.

output "ngfw_resource_group_name" {
  description = "The name of the Azure Resource Group containing the Cloud NGFW."
  value       = azurerm_resource_group.ngfw_rg.name
}

output "cloud_ngfw_name" {
  description = "The name of the deployed Cloud NGFW instance."
  value       = azurerm_palo_alto_next_generation_firewall_virtual_network_appliance.ngfw.name
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
