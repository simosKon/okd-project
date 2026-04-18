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
  http_port_min  = 8600
  http_port_max  = 8610

  boot_wait = "15s"
  boot_keygroup_interval = "750ms"
  boot_command = [
    "<up><wait>",
    "<tab><wait>",
    " inst.text ip=dhcp inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg inst.nomediacheck",
    "<enter>"
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
    environment_vars = [
      "ANSIBLE_ROOT_SSH_PUBLIC_KEY=${var.ansible_root_ssh_public_key}"
    ]
    inline = [
      "if [ -n \"$ANSIBLE_ROOT_SSH_PUBLIC_KEY\" ]; then mkdir -p /root/.ssh && chmod 700 /root/.ssh && touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && grep -qxF \"$ANSIBLE_ROOT_SSH_PUBLIC_KEY\" /root/.ssh/authorized_keys || echo \"$ANSIBLE_ROOT_SSH_PUBLIC_KEY\" >> /root/.ssh/authorized_keys; fi",
      "systemctl enable vmtoolsd qemu-guest-agent sshd",
      "cloud-init clean --logs || true",
      "dnf clean all || true",
      "rm -f /etc/ssh/ssh_host_*",
      "truncate -s 0 /etc/machine-id"
    ]
  }
}
