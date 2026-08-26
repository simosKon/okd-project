# vSphere credentials (set password via env var: TF_VAR_vsphere_password)
# export TF_VAR_vsphere_password='YOUR_REAL_PASSWORD'
vsphere_server = "192.168.1.10"

# vSphere inventory
datacenter    = "LabDatacenter"
cluster       = "OKD"
datastore     = "VMs"
network       = "VM Network"
template_name = "rhel_9.4-template"
guest_domain  = "lab.local"

# haproxy vm settings
haproxy_name        = "haproxy"
haproxy_mac_address = "00:50:56:ad:10:15"
haproxy_cpu         = 2
haproxy_memory_mb   = 4096

# optional
vm_folder = "OKD"
