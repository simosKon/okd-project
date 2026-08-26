vcenter_server   = "vcenter.lab.local"

datacenter = "LabDatacenter"
cluster    = "OKD"
datastore  = "VMs"
network    = "VM Network"
folder     = "OKD"

template_name = "rhel_9.4-template"
cpu           = 2
memory        = 4096
disk_size_mb  = 20480

# Example datastore path after upload_iso.sh
iso_datastore_path = "[VMs] ISO/rhel-9.4-x86_64-dvd.iso"

# Must match rootpw in http/ks.cfg unless you customize ks.cfg
ssh_username = "root"
ansible_root_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDXB7JUxoaaXfbFi5OxopX7oIlFuVJCllZ3LtItfR1WVqhe75Wxj1CipGksME3OXLHZDFr+dSIqR9NHiS2zDj3yi+zpyyDiqCnKDo1IY/1FwuEJsWU6fdDwebOgQD4EatSswQmjKL9gKduiTiW3LZMUsEYw9Omy6YEMXbVu690b78rXVK5HKOw03Ke8nEB6wDK+TN+HWIKdqwTTGgQXYkEvaspPPMUvCWEDLLBTu8IpOZwxXQMC8IyfUsb89PaDLHFXWi0LPdz7639v7dwoDCiIV5AfC16rYhF/vjxr4TFeAih5IXpqXaR/y+1iEIXwzCfDfDW66L7aN2DQXeiW3pDPRrP0vDa1e+IKNXN4VMlW8IGwLMO3uT0VFXBUi0VzcXAP+rlCTj39fHR+wzgybUXEmQYPJGYvnUC45zrzjNuy+WZLiTymPY8KKI8TFT4zHJj7HHoJXnV/kXcKZE+I0exl2FQ3QzmhmgPbvth+ZoZ52ikn5/cvZRU9BGoszSH/7ds= root@ansible.test.local"
