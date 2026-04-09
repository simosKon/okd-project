# Infra Roles Guide

> Canonical single-flow runbook: see `README.md` in repository root.
> This file remains as extended infra reference.

This project assumes working knowledge of:
- vSphere administration
- DNS and basic networking concepts (VIPs, load balancing)
- Linux system administration
- Basic OpenShift/OKD architecture

This is not a beginner guide.

## README Structure
1. Quick Start
2. Architecture Diagram and Flow Explanation
3. Assumptions and Scope
4. Variables / Execution / Validation
5. Re-run Semantics
6. Troubleshooting and FAQ
7. Known Limitations and Future Improvements

## QUICK START
1. Run preflight:
   - `ansible-playbook -i inventory.ini playbooks/06_pre_install_infra.yml`
2. Set required infra vars in `group_vars/all.yml`.
3. Run:
   - `ansible-playbook -i inventory.ini playbooks/01_core_infra.yml`
4. Validate:
   - DNS (`named`) is active and resolving expected records
   - HAProxy is active and listening on `6443`, `22623`, `80`, `443`
   - firewalld rules are applied

## ONE-SCREEN RUNBOOK
```bash
# 0) Infra precheck
ansible-playbook -i inventory.ini playbooks/06_pre_install_infra.yml

# 1) Core infra (DNS + baseline + HAProxy)
ansible-playbook -i inventory.ini playbooks/01_core_infra.yml

# 2) Optional platform/vCenter flow
ansible-playbook -i inventory.ini playbooks/00_platform_roles.yml

# 3) Quick validation
systemctl status named
systemctl status haproxy
ss -lntp | egrep '6443|22623|80|443'
```

Warning:
- Keep platform role toggles (`platform_roles.*`) aligned with your intent before running.
- If running from a world-writable path, Ansible may ignore project `ansible.cfg`.
- ESXi hosts and the DNS server must already be installed and reachable before running this playbook.
- NFS server OS must already be installed and reachable if you use `storage_backend: nfs`.

## 1. Control Host Requirements
All commands must run from a control host that:
- has Ansible installed
- has access to this repo and `inventory.ini`
- can SSH to `dns`, `haproxy`, and other target hosts
- has network access to vCenter if `vcenter_*` roles are enabled
- has required VMware tooling for platform roles:
  - `community.vmware` Ansible collection
  - `govc` CLI (required only for `vcenter_create_vsan_datastore` disk-group workflow)

Install example:
```bash
ansible-galaxy collection install community.vmware
govc version
```

Environment prerequisite:
- ESXi hosts are already installed.
- DNS server OS is already installed.
- NFS server OS is already installed (when using NFS backend).

## 1A. Prereqs Checklist (Before Any Run)
- Pre-existing hosts:
- control host (Ansible runner)
- `dns` VM (OS installed, reachable over SSH)
- `haproxy` VM (OS installed, reachable over SSH)
- `nfs` VM (OS installed, reachable over SSH) when `storage_backend: nfs`
- ESXi hosts installed and reachable by vCenter workflow (if used)
- Inventory is mapped correctly (`dns`, `haproxy`, `infra`, `rhel`)
- Network plan is fixed (subnet, gateway, DNS IP, VIP IPs)
- DNS domain values in vars are final before first run
- If using vCenter roles, required credentials/files are set in vars/secrets

## 1B. Inventory Mapping Example
```ini
[dns]
dns ansible_host=192.168.1.8 ansible_user=root

[haproxy]
haproxy ansible_host=192.168.1.15 ansible_user=root

[ansible]
ansible ansible_host=192.168.1.13 ansible_user=root

[infra:children]
dns
haproxy

[rhel:children]
dns
haproxy
ansible
```

## 2. Architecture Summary
```text
Ansible 01_core_infra.yml
        ->
DNS First (dns)
        ->
Baseline Platform Roles (rhel)
        ->
HAProxy Roles (haproxy)
        ->
Infra Converged State
```

Optional separate flow:
```text
Ansible 00_platform_roles.yml
        ->
vCenter Roles (localhost)
```

## 2A. Architecture Diagram
```text
Pre-existing: ESXi installed + DNS host OS installed + HAProxy host OS installed
                                |
                                v
Optional: 00_platform_roles.yml (vCenter deploy/configure flow)
                                |
                                v
01_core_infra.yml
  - DNS firewall + DNS role
  - baseline platform roles (optional via toggles)
  - HAProxy firewall + HAProxy role
                                |
                                v
Infra ready for OKD prep + Terraform stages
```

## 2B. Flow Explanation
- DNS is configured first because other components rely on name resolution.
- Baseline host roles are controlled by `platform_roles.*` flags.
- HAProxy is configured in the same infra run and is mandatory for this OKD UPI flow.
- Optional vCenter roles are intentionally split into a separate playbook (`00_platform_roles.yml`).

Responsibility split:
- `01_core_infra.yml`: DNS/HAProxy/baseline OS convergence on infra hosts.
- `00_platform_roles.yml`: optional vCenter lifecycle and datastore/network automation.
- OKD lifecycle itself is handled later by `02_okd_upi_prepare.yml` + Terraform + installer waits.

## 3. Scope
Included:
- platform baseline roles: `ansible_user`, `ntp_conf`, `sssd_conf`
- infra service roles: `firewall_conf`, `dns_conf`, `haproxy_conf`
- optional vCenter roles: `vcenter_deploy`, `vcenter_configure`, `vcenter_create_datacenter`, `vcenter_create_clusters`, `vcenter_add_esxi_hosts`, `vcenter_configure_networks`, `vcenter_configure_vds`, `vcenter_configure_vmkernel`, `vcenter_join_esxi_cluster`, `vcenter_configure_clusters`, `vcenter_create_nfs_datastore`, `vcenter_create_vsan_datastore`, `vcenter_add_licenses`

Excluded:
- OKD artifact generation role (`okd_upi_prepare`)

## 3A. Scope Boundaries
Supported scope:
- vSphere-centered lab infra automation
- DNS + HAProxy + baseline platform roles
- optional vCenter role flow via `playbooks/00_platform_roles.yml`

Not supported yet:
- multi-VLAN orchestration logic
- IPv6-only infra model
- disconnected/proxy-heavy full automation path

## 3B. Assumptions
- Operators can manage vSphere, DNS zones, HAProxy listeners, and Linux services.
- Inventory groups are accurate and hosts are reachable over SSH.
- ESXi and DNS server installation is already completed before infra roles run.
- If vCenter roles are enabled, required OVA path/credentials are already valid.

## 4. Required Variables
Main file: `group_vars/all.yml`

Lab baseline used in this project:
- 2 ESXi hosts
- NFS used as default shared datastore backend
- per ESXi host: `52 GB RAM`, `12 vCPU`
- vMotion enabled
- DRS enabled

If your environment has more than 2 ESXi hosts:
- add all extra ESXi hosts in vars (`infrastructure.esxi`)
- ensure DNS records/zone data include those additional ESXi hosts

vSphere minimum assumptions for this lab profile:
- 2 ESXi hosts were used in baseline
- datastore can be NFS (default path) or vSAN (optional path)
- vMotion/DRS were enabled (recommended, not hard-required for role execution)
- If no vSAN is available, use any shared datastore and update vars accordingly

Nested ESXi disk layout used for vSAN in this project:
- `Hard Disk 1` (`30 GB`): ESXi OS/boot disk (not used in vSAN disk groups)
- `Hard Disk 2` (`100 GB`): vSAN capacity
- `Hard Disk 3` (`20 GB`): vSAN cache (must be marked as SSD in nested lab)
- `Hard Disk 4` (`100 GB`): vSAN capacity

Important for nested labs:
- vSAN auto-claim is disabled by default in this repo (`infrastructure.vcenter.vsan.auto_claim_storage: false`).
- In nested ESXi, virtual disks are often detected as HDD; if cache disk is not marked SSD, disk group creation can fail or map incorrectly.
- Ensure the `20 GB` disk is SSD-flagged before creating vSAN disk groups.
- `vcenter_create_vsan_datastore` expects explicit `infrastructure.vcenter.vsan.disk_groups` mapping per ESXi host.

Minimum infra variables to verify:
- `network.*`
- `infrastructure.dns_server.*`
- `infrastructure.haproxy_server.*`
- `infrastructure.load_balancer_vips`
- `infrastructure.vcenter.deploy_storage_type` (`local_esxi` or `nfs_pre_mounted`)
- `infrastructure.bootstrap.*`
- `infrastructure.master[]`
- `infrastructure.worker[]`
- `firewall.services`
- `firewall.ports`
- `platform_roles.*`

Secrets policy:
- do not commit secrets
- use vault/secret files for credentials (AD/vCenter/etc.)

## 5. Execution Flow
### 5.1 DNS First (`dns`)
Roles/tasks:
- `firewall_conf` with profile `dns`
- `dns_conf`

### 5.2 NFS First (optional but pre-vCenter for NFS backend) (`nfs`)
Roles/tasks:
- `firewall_conf` with profile `nfs`
- `lvm_create` (when `platform_roles.nfs_lvm_enabled=true`)
- `nfs_conf` (when `platform_roles.nfs_conf_enabled=true`)

### 5.3 Baseline Platform Roles (`rhel`)
Roles:
- `ansible_user`
- `ntp_conf`
- `sssd_conf`

Gated by:
- `platform_roles.ansible_user_enabled`
- `platform_roles.ntp_conf_enabled`
- `platform_roles.ad_join_enabled` or `platform_roles.sssd_conf_enabled`

### 5.4 HAProxy Roles (`haproxy`)
Roles/tasks:
- `firewall_conf` with profile `haproxy`
- `haproxy_conf`

### 5.5 Optional vCenter Roles (`localhost`)
Playbook:
- `playbooks/00_platform_roles.yml`

Roles:
- `vcenter_deploy`
- `vcenter_configure`
- `vcenter_create_datacenter`
- `vcenter_create_clusters`
- `vcenter_add_esxi_hosts`
- `vcenter_configure_networks`
- `vcenter_configure_vds`
- `vcenter_configure_vmkernel`
- `vcenter_join_esxi_cluster`
- `vcenter_configure_clusters`
- `vcenter_create_nfs_datastore`
- `vcenter_create_vsan_datastore`
- `vcenter_add_licenses`

Decision guide:
```text
Do you already have a working vCenter?
  Yes -> skip `vcenter_deploy` (and any bootstrap-vCenter roles you do not need)
  No  -> set `platform_roles.vcenter_deploy_enabled=true` and run 00 flow

Do you want vDS networking?
  Yes -> set `platform_roles.vcenter_configure_vds_enabled=true`
  No  -> use `vcenter_configure_networks` (vSS path)

Do you want AD/SSO integration?
  Yes -> enable `platform_roles.ad_join_enabled=true` and provide AD vars/secrets
  No  -> keep AD-related toggles disabled
```

### 5.6 Re-run Behavior
`playbooks/01_core_infra.yml` is idempotent and can be re-run safely.

## 5A. Storage Backend Switch (`nfs` <-> `vsan`)
Set in `group_vars/all.yml`:
```yaml
storage_backend: nfs   # or vsan
```

Decision matrix:
| Scenario | Recommended backend | Why |
|---|---|---|
| 1 ESXi host lab | `nfs` | vSAN is not practical for single-host labs |
| 2 ESXi lab without witness/licensing plan | `nfs` | simpler and more predictable |
| 2+ ESXi with proper vSAN plan | `vsan` | native shared datastore path |
| Nested lab where cache SSD marking is hard | `nfs` | avoids vSAN disk-group fragility |

NFS prerequisites:
- `nfs` host exists in inventory and is reachable
- NFS roles enabled as needed:
  - `platform_roles.nfs_lvm_enabled`
  - `platform_roles.nfs_conf_enabled`
- vCenter datastore role enabled:
  - `platform_roles.vcenter_create_nfs_datastore_enabled=true`
- Important bootstrap rule:
  - if `vcenter_deploy_enabled=true` and you want vCenter VM on NFS, pre-mount the NFS datastore on standalone ESXi before running `vcenter_deploy`
  - `vcenter_create_nfs_datastore` is a post-vCenter role (it cannot create the first datastore for the initial vCenter deployment)

vSAN prerequisites:
- `storage_backend: vsan`
- vSAN-capable/license-ready environment
- explicit disk groups in `infrastructure.vcenter.vsan.disk_groups`
- cache disk is SSD-marked in nested labs
- vSAN vmkernel is created only when `storage_backend=vsan`
- vCenter datastore role enabled:
  - `platform_roles.vcenter_create_vsan_datastore_enabled=true`

Important:
- Changing `storage_backend` after initial infra converge should be treated as a rebuild scenario.
- In-place migration between NFS and vSAN is out of scope for this automation.

## 6. Run Commands
Full core infra run:
```bash
ansible-playbook -i inventory.ini playbooks/01_core_infra.yml
```
Prerequisite for this run:
- `dns` and `haproxy` hosts must already exist in inventory and be reachable (OS installed).
- DNS/HAProxy services do **not** need to be pre-configured; this playbook configures them.

Tag examples:
```bash
# only DNS block
ansible-playbook -i inventory.ini playbooks/01_core_infra.yml --tags dns

# only baseline platform roles
ansible-playbook -i inventory.ini playbooks/01_core_infra.yml --tags baseline
```

vCenter-only run (separate flow):
```bash
ansible-playbook -i inventory.ini playbooks/00_platform_roles.yml
```

Infra services only (disable baseline):
```bash
ansible-playbook -i inventory.ini playbooks/01_core_infra.yml \
  -e platform_roles.ansible_user_enabled=false \
  -e platform_roles.ntp_conf_enabled=false \
  -e platform_roles.ad_join_enabled=false \
  -e platform_roles.sssd_conf_enabled=false
```

## 7. Done State
Infra is considered successful when:
- DNS service is `active` and expected records resolve
- HAProxy service is `active` and listeners are present on `6443`, `22623`, `80`, `443`
- HAProxy VIP IPs are present on the target interface
- firewalld is `active` and required services/ports are open
- playbook ends with `failed=0` and `unreachable=0`

## 8. Common Failure Causes
- wrong inventory group mapping (`dns`, `haproxy`, `infra`, `rhel`)
- invalid/partial `group_vars/all.yml` values
- running from world-writable path so project `ansible.cfg` is ignored
- DNS/HAProxy host NIC mismatch when assigning VIPs
- disabled `platform_roles.*` flags when roles were expected to run

## 8A. Safe Re-run Policy
Safe to re-run:
- `playbooks/06_pre_install_infra.yml`
- `playbooks/01_core_infra.yml`
- `playbooks/00_platform_roles.yml` (roles remain gated by `platform_roles.*`)

Use caution when re-running:
- vCenter deploy/config roles if underlying vSphere objects were modified manually

## Re-run Semantics
- `06_pre_install_infra.yml`: read-only validation, safe for frequent use.
- `01_core_infra.yml`: idempotent infra convergence; expected to be re-run.
- `00_platform_roles.yml`: safe when toggles are intentional and current vSphere state is understood.
- Re-runs after manual drift may show changes; prefer fixing drift in code/vars first.

## 9. Networking, DNS, HAProxy Assumptions
Networking:
- DNS, HAProxy, bootstrap, masters, worker, and VIPs are expected in the same routed lab network.
- HAProxy VIPs are added on the HAProxy host active interface via `nmcli` (role-managed).

DNS:
- Cluster name/base domain define FQDNs (example: `okd` + `lab.local` => `okd.lab.local`).
- This automation assumes your DNS server is authoritative for the cluster domain.
- Required records include:
- `api.<cluster>.<domain>` -> API VIP
- `api-int.<cluster>.<domain>` -> API VIP
- `*.apps.<cluster>.<domain>` -> Ingress VIP
- `bootstrap`, `master01-03`, `worker01` host records
- Reverse zone is generated by `dns_conf` in this project.

Quick DNS checks:
```bash
dig +short api.okd.lab.local @192.168.1.8
dig +short api-int.okd.lab.local @192.168.1.8
dig +short test.apps.okd.lab.local @192.168.1.8
```

HAProxy:
- listeners expected: `6443`, `22623`, `80`, `443`
- bootstrap backend exists during bootstrap phase
- bootstrap backend is removed by `playbooks/03_post_bootstrap_haproxy.yml`

## 10. Implementation FAQ (Infra)
### 10.1 What exactly does `00_platform_roles.yml` require?
- It runs on the control host (`hosts: localhost`), not on vCenter.
- It requires required Ansible collections/modules for VMware and network reachability to vCenter/ESXi endpoints.
- If `vcenter_deploy` is enabled, `infrastructure.vcenter.vcsa_ova_file` must be valid and reachable from control host.
- Role toggles decide what is executed:
- deploy/configure/create-datacenter/add-licenses are independent flags.
- For networking path:
- `vcenter_configure_vds_enabled=true` uses vDS path and skips `vcenter_configure_networks` (vSS path).
- For vDS host attachment, set `infrastructure.vcenter.vds.host_uplinks` with per-ESXi vmnic lists.
- Host workflow split:
- `vcenter_add_esxi_hosts`: add hosts to vCenter inventory
- `vcenter_configure_vmkernel`: configure required vmkernel adapters (on vSS or on vDS depending on selected networking path)
- `vcenter_join_esxi_cluster`: move hosts into target cluster
- `vcenter_join_esxi_cluster` now fails fast if vMotion/vSAN are enabled but required VMkernel settings are missing.
- `vcenter_create_nfs_datastore` mounts NFS datastore from `infrastructure.nfs_server` (default storage path).
- `vcenter_create_vsan_datastore` enables vSAN but does not replace manual nested-lab SSD marking/disk-group discipline.
- `vcenter_configure` AD/SSO integration runs only when `platform_roles.ad_join_enabled=true`.

### 10.2 HAProxy VIP interface behavior
- VIPs are attached by `haproxy_conf` with `nmcli`.
- If `infrastructure.haproxy_server.interface` is set, that NIC is used.
- If empty, role picks the first active non-loopback connection.
- For multi-NIC setups, set `infrastructure.haproxy_server.interface` explicitly.

### 10.3 DNS reverse zone behavior
- Reverse zone is generated from `network.base` (example `192.168.1` -> `1.168.192.in-addr.arpa`).
- Re-runs update templates idempotently.
- If you already have external DNS authority, integrate via zone delegation/forwarding strategy before running.

### 10.4 Firewall scope
- `firewall_conf` opens profile-driven services/ports from `firewall.services` and `firewall.ports`.
- Current infra profile focuses on DNS and HAProxy endpoints.
- Node-to-node OpenShift traffic is not managed by this role; it applies only to hosts where the role runs.

## 11. Known Limitations
- Baseline is optimized for lab topology, not generalized enterprise topologies.
- Single-network assumptions are embedded in examples and defaults.
- HAProxy VIP handling assumes predictable interface behavior unless explicitly pinned.
- vCenter deployment automation is optional and not required for every environment.


## 12. Future Improvements
- Add stronger preflight coverage for NIC naming and DNS zone authority conflicts.
- Add optional multi-NIC/multi-VLAN patterns with explicit examples.
- Add role-by-role execution matrix with dependencies and expected artifacts.

## 13. OKD Post-Install Validation (Cross-Doc Pointer)
After OKD install completes, run:
```bash
ansible-playbook -i inventory.ini playbooks/05_post_install_validation.yml
```

This generates:
- `reports/post-install-validation-latest.json`
- `reports/post-install-validation-latest.md`

## 14. Pre-Install Infra Validation Report
Run before infra changes:
```bash
ansible-playbook -i inventory.ini playbooks/06_pre_install_infra.yml
```
Strict mode (fail on blockers):
```bash
ansible-playbook -i inventory.ini playbooks/06_pre_install_infra.yml -e preinfra_fail_on_critical=true
```

This validates and reports:
- inventory groups and critical IP vars (`dns`, `haproxy`, `nfs` for NFS backend)
- reachability checks for DNS/HAProxy/NFS and vCenter (when enabled)
- `vcsa_ova_file` existence when `vcenter_deploy_enabled=true`
- `infrastructure.vcenter.deploy_storage_type` (`local_esxi` or `nfs_pre_mounted`) consistency checks
- vCenter/ESXi/AD credential prerequisites based on enabled role toggles
- tooling hint for `community.vmware`

Reports:
- `reports/pre-install-infra-latest.json`
- `reports/pre-install-infra-latest.md`

