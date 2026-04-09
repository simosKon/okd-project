variable "vcenter_server" {
  type = string
}

variable "vcenter_username" {
  type = string
}

variable "vcenter_password" {
  type      = string
  sensitive = true
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

variable "folder" {
  type    = string
  default = ""
}

variable "template_name" {
  type    = string
  default = "rhel_9.4"
}

variable "cpu" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 4096
}

variable "disk_size_mb" {
  type    = number
  default = 20480
}

variable "iso_datastore_path" {
  type        = string
  description = "Datastore ISO path, e.g. [NFS-OKD] ISO/rhel-9.4-x86_64-dvd.iso"
}

variable "ssh_username" {
  type    = string
  default = "root"
}

variable "ssh_password" {
  type      = string
  sensitive = true
}
