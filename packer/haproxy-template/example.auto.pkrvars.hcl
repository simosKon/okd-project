vcenter_server   = "vcenter.example.local"
vcenter_username = "administrator@vsphere.local"

datacenter = "LabDatacenter"
cluster    = "OKD"
datastore  = "NFS-OKD"
network    = "VM Network"
folder     = "OKD"

template_name = "rhel_9.4-template"
cpu           = 2
memory        = 4096
disk_size_mb  = 20480

# Example datastore path after upload_iso.sh
iso_datastore_path = "[NFS-OKD] ISO/rhel-9.4-x86_64-dvd.iso"

# Must match rootpw in http/ks.cfg unless you customize ks.cfg
ssh_username = "root"
