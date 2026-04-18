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
}

variable "vsphere_password" {
  type      = string
  sensitive = true
}

variable "vsphere_server" {
  type = string
}

variable "datacenter" {
  type = string
}

variable "cluster" {
  type = string
}

variable "datastore" {
  type = string
}

variable "network" {
  type = string
}

variable "template_name" {
  type        = string
  description = "VM template name used for HAProxy clone"
}

variable "vm_folder" {
  type        = string
  default     = ""
  description = "Optional vSphere VM folder (empty = root VM folder)"
}

variable "haproxy_name" {
  type    = string
  default = "haproxy"
}

variable "guest_domain" {
  type        = string
  default     = "localdomain"
  description = "Guest OS DNS domain used during vSphere clone customization."
}

variable "root_ssh_public_key" {
  type        = string
  default     = ""
  description = "Optional SSH public key injected into root authorized_keys via cloud-init guestinfo."
}

variable "haproxy_mac_address" {
  type        = string
  description = "Static MAC for HAProxy VM"
  default     = "00:50:56:ad:10:15"
  validation {
    condition     = can(regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", var.haproxy_mac_address))
    error_message = "haproxy_mac_address must be a valid MAC address (aa:bb:cc:dd:ee:ff)."
  }
}

variable "haproxy_cpu" {
  type    = number
  default = 2
}

variable "haproxy_memory_mb" {
  type    = number
  default = 4096
}

data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

locals {
  vm_folder_name    = trimspace(var.vm_folder)
  vm_folder_enabled = local.vm_folder_name != ""
  root_ssh_public_key_trimmed = trimspace(var.root_ssh_public_key)
  haproxy_metadata = yamlencode({
    instance_id    = var.haproxy_name
    local_hostname = "${var.haproxy_name}.${var.guest_domain}"
  })
  haproxy_userdata = yamlencode({
    disable_root = false
    ssh_pwauth   = true
    users = local.root_ssh_public_key_trimmed != "" ? [
      "default",
      {
        name                = "root"
        ssh_authorized_keys = [local.root_ssh_public_key_trimmed]
      }
    ] : ["default"]
  })
  haproxy_guestinfo_config = {
    "guestinfo.metadata"          = base64encode(local.haproxy_metadata)
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = base64encode(local.haproxy_userdata)
    "guestinfo.userdata.encoding" = "base64"
  }
}

resource "vsphere_virtual_machine" "haproxy" {
  name             = var.haproxy_name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = local.vm_folder_enabled ? local.vm_folder_name : null

  num_cpus = var.haproxy_cpu
  memory   = var.haproxy_memory_mb
  guest_id = data.vsphere_virtual_machine.template.guest_id

  firmware                = data.vsphere_virtual_machine.template.firmware
  efi_secure_boot_enabled = false

  scsi_type = data.vsphere_virtual_machine.template.scsi_type

  network_interface {
    network_id     = data.vsphere_network.network.id
    adapter_type   = data.vsphere_virtual_machine.template.network_interface_types[0]
    use_static_mac = true
    mac_address    = var.haproxy_mac_address
  }

  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template.disks[0].size
    thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = substr(var.haproxy_name, 0, 63)
        domain    = var.guest_domain
      }

      network_interface {}
    }
  }

  extra_config = merge({
    "disk.EnableUUID"   = "TRUE"
    "stealclock.enable" = "TRUE"
  }, local.haproxy_guestinfo_config)
}

output "haproxy_vm_name" {
  value = vsphere_virtual_machine.haproxy.name
}
