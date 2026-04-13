terraform {
  required_version = ">= 1.5.0"

  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.6"
    }
  }
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

variable "vsphere_user" {
  type = string
  validation {
    condition     = length(trimspace(var.vsphere_user)) > 0
    error_message = "vsphere_user must not be empty."
  }
}

variable "vsphere_password" {
  type      = string
  sensitive = true
}

variable "vsphere_server" {
  type = string
  validation {
    condition     = length(trimspace(var.vsphere_server)) > 0
    error_message = "vsphere_server must not be empty."
  }
}

variable "datacenter" {
  type = string
  validation {
    condition     = length(trimspace(var.datacenter)) > 0
    error_message = "datacenter must not be empty."
  }
}

variable "vm_folder" {
  type        = string
  description = "vSphere VM folder name to create/manage for shared automation."
  validation {
    condition     = length(trimspace(var.vm_folder)) > 0
    error_message = "vm_folder must not be empty."
  }
}

data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

locals {
  vm_folder_name = trimspace(var.vm_folder)
}

resource "vsphere_folder" "vm_folder" {
  path          = local.vm_folder_name
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc.id
}

output "vm_folder_path" {
  value       = vsphere_folder.vm_folder.path
  description = "Managed vSphere VM folder path."
}
