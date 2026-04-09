# OKD Unified Project (3 Masters + 1 Worker)

Standalone Ansible project for infra + OKD UPI preparation.

## Playbooks
- `playbooks/01_core_infra.yml`: combined core infra flow (platform roles + DNS + HAProxy + firewall).
- `playbooks/02_okd_upi_prepare.yml`: generate install-config, manifests, ignition and base64 artifacts.
- `playbooks/03_post_bootstrap_haproxy.yml`: remove bootstrap backends after bootstrap completion.
- `playbooks/00_platform_roles.yml`: optional vCenter-only flow.

## Required configuration
Edit split vars under `group_vars/all/` and set at least:
- `okd.ssh_public_key`
- `okd.pull_secret`

For AD/SSSD roles:
- `ad_admin_user`
- `ad_admin_password`

For vCenter roles:
- `vcenter_password`
- `esxi_password`
- `infrastructure.vcenter.vcsa_ova_file` (for deploy)
- license keys if using `vcenter_add_licenses`

For ansible_user role:
- `infrastructure.ansible_server.ansible_admin_ssh_key`

## Secrets Policy (Do Not Skip)
Do **not** store sensitive values directly in `group_vars/all/*.yml` or commit them to git.
Keep secrets in vault/secret files and reference them from vars.

Sensitive variables to keep in secrets:
- `okd.pull_secret`
- `ad_admin_user`, `ad_admin_password`
- `vcenter_password`, `esxi_password`
- `infrastructure.ansible_server.ansible_admin_ssh_key` (recommended)

Example pattern:
- In `group_vars/all/vcenter.yml`: `vcenter_password: "{{ vault_vcenter_password }}"`
- In secret file: `vault_vcenter_password: "<real-value>"`
## Safety toggles
`platform_roles` flags in `group_vars/all/core.yml` control heavy operations. By default, vCenter and AD join flows are disabled.

## Run sequence
```bash
ansible-playbook playbooks/01_core_infra.yml
ansible-playbook playbooks/02_okd_upi_prepare.yml
# optional, separate flow
ansible-playbook playbooks/00_platform_roles.yml
# after bootstrap-complete
ansible-playbook playbooks/03_post_bootstrap_haproxy.yml
```

## Notes
- This project uses `platform: none`, so VM creation and `guestinfo.ignition.config.*` injection are manual in vSphere.
- `okd_upi_prepare` auto-downloads `openshift-install`, `oc`, and `kubectl` from official OKD release URLs based on `okd.version`.
- vCenter roles require VMware collection/modules on the control node (`community.vmware`).
- `playbooks/00_platform_roles.yml` is the vCenter-only playbook.
- `playbooks/01_core_infra.yml` is the core infra playbook.

