packer {
  required_plugins {
    vsphere = {
      source  = "github.com/hashicorp/vsphere"
      version = ">= 1.1.1"
    }
  }
}

source "vsphere-iso" "rhel94_haproxy" {
  vcenter_server      = var.vcenter_server
  username            = var.vcenter_username
  password            = var.vcenter_password
  insecure_connection = true

  datacenter = var.datacenter
  cluster    = var.cluster
  datastore  = var.datastore
  folder     = var.folder != "" ? var.folder : null

  vm_name       = var.template_name
  guest_os_type = "rhel9_64Guest"
  CPUs          = var.cpu
  RAM           = var.memory
  RAM_reserve_all = false

  disk_controller_type = ["pvscsi"]
  storage {
    disk_size             = var.disk_size_mb
    disk_thin_provisioned = true
  }

  network_adapters {
    network      = var.network
    network_card = "vmxnet3"
  }

  iso_paths = [var.iso_datastore_path]
  cdrom_type = "sata"

  http_directory = "http"

  boot_wait = "5s"
  boot_command = [
    "<up><wait>",
    "e<wait>",
    "<down><down><down><end>",
    " inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
    "<ctrl-x>"
  ]

  communicator   = "ssh"
  ssh_username   = var.ssh_username
  ssh_password   = var.ssh_password
  ssh_timeout    = "40m"
  shutdown_command = "shutdown -P now"

  convert_to_template = true
}

build {
  name    = "rhel94-haproxy-template"
  sources = ["source.vsphere-iso.rhel94_haproxy"]

  provisioner "shell" {
    inline = [
      "dnf -y update",
      "dnf -y install open-vm-tools cloud-init qemu-guest-agent",
      "systemctl enable vmtoolsd qemu-guest-agent",
      "dnf clean all",
      "rm -f /etc/ssh/ssh_host_*",
      "truncate -s 0 /etc/machine-id"
    ]
  }
}
