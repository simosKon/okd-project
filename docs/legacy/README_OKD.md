# README - OKD 4.18 UPI (3 Masters + 1 Worker)

> Canonical single-flow runbook: see `README.md` in repository root.
> This file remains as extended OKD reference.

This project assumes working knowledge of:
- vSphere administration
- DNS and basic networking concepts (VIPs, load balancing)
- Linux system administration
- Basic OpenShift/OKD architecture

This is not a beginner guide.

## README Structure
1. Quick Start / Run Card
2. Architecture Diagram and Flow Explanation
3. Assumptions and Scope
4. Prerequisites / Variables / Execution Flow
5. Re-run Semantics
6. Validation, Troubleshooting, FAQ
7. Known Limitations and Future Improvements

## QUICK START
1. Run infra precheck:
   - `ansible-playbook -i inventory.ini playbooks/06_pre_install_infra.yml`
2. Set required vars in `group_vars/all.yml`.
3. Run:
   - `ansible-playbook playbooks/01_core_infra.yml`
   - `ansible-playbook playbooks/02_okd_upi_prepare.yml`
4. Run OKD precheck (strict before Terraform):
   - `ansible-playbook -i inventory.ini playbooks/07_pre_install_okd.yml -e preokd_require_ignition_files=true`
5. Run Terraform:
   - `cd terraform`
   - `terraform init`
   - `terraform validate`
   - `terraform plan`
   - `terraform apply`
6. Wait bootstrap-complete:
   - `/root/okd-tools/openshift-install --dir /root/okd-install wait-for bootstrap-complete --log-level=debug`
7. Run:
   - `ansible-playbook playbooks/03_post_bootstrap_haproxy.yml`
8. Wait install-complete:
   - `/root/okd-tools/openshift-install --dir /root/okd-install wait-for install-complete --log-level=debug`
9. Generate post-install validation report:
   - `ansible-playbook -i inventory.ini playbooks/05_post_install_validation.yml`

Warning:
- Do NOT run Terraform before `playbooks/02_okd_upi_prepare.yml` finishes.
- Ignition base64 files (`bootstrap.64`, `master.64`, `worker.64`) must exist before `terraform apply`.

IMPORTANT:
- Terraform must run on a host that can read the ignition files referenced in `terraform/terraform.tfvars`.
- If ignitions are under `/root/okd-install`, run Terraform on that same control host (or copy files and update paths).

## ONE-SCREEN RUNBOOK
```bash
# 0) Infra precheck
ansible-playbook -i inventory.ini playbooks/06_pre_install_infra.yml

# 1) Infra converge
ansible-playbook -i inventory.ini playbooks/01_core_infra.yml

# 2) OKD artifacts (install-config + ignitions)
ansible-playbook playbooks/02_okd_upi_prepare.yml

# 3) OKD precheck (strict)
ansible-playbook -i inventory.ini playbooks/07_pre_install_okd.yml -e preokd_require_ignition_files=true

# 4) Terraform apply (run where ignition paths exist)
cd terraform
terraform init
terraform validate
terraform plan
terraform apply

# 5) Bootstrap complete
/root/okd-tools/openshift-install --dir /root/okd-install wait-for bootstrap-complete --log-level=debug

# 6) Remove bootstrap from HAProxy (+ lab helpers)
ansible-playbook playbooks/03_post_bootstrap_haproxy.yml

# 7) Install complete
/root/okd-tools/openshift-install --dir /root/okd-install wait-for install-complete --log-level=debug

# 8) Post-install validation report
ansible-playbook -i inventory.ini playbooks/05_post_install_validation.yml
```

## Architecture Diagram
```text
Pre-existing: DNS host, HAProxy host, ESXi host(s), optional vCenter flow
                                |
                                v
Ansible preflight (infra stage) + 01_core_infra.yml
                                |
                                v
02_okd_upi_prepare.yml (install-config + ignition .64 files + tools)
                                |
                                v
Ansible preflight (terraform stage)
                                |
                                v
Terraform (bootstrap + masters + workers on vSphere)
                                |
                                v
wait-for bootstrap-complete
                                |
                                v
03_post_bootstrap_haproxy.yml (remove bootstrap backend + helper actions)
                                |
                                v
wait-for install-complete -> cluster converge
```

## Flow Explanation
- Ansible prepares infra and install artifacts.
- Terraform only provisions VMs and injects ignition data into them.
- Bootstrap is temporary and must be removed from HAProxy after bootstrap-complete.
- Final convergence is validated with `oc` checks and installer wait commands.

## Responsibility Split
- Ansible: host configuration + OKD artifact generation (`install-config`, ignitions, tool links).
- Terraform: immutable VM provisioning only (clone + guestinfo ignition injection).
- `openshift-install`: cluster lifecycle orchestration and convergence checks (`wait-for ...`).

## 1. Control Host Requirements
All commands must be executed from the control host that:
- has Ansible
- has Terraform
- has `openshift-install`, `oc`, `kubectl`
- has access to `/root/okd-install`
- has network access to vCenter

Important:
- Use absolute kubeconfig path:
  - `export KUBECONFIG=/root/okd-install/auth/kubeconfig`
- Do not use `./auth/kubeconfig` unless current directory is exactly `/root/okd-install`.

## 1A. Prereqs Checklist (Copy/Paste)
- Pre-existing hosts:
- control host (Ansible/Terraform runner)
- `dns` VM (OS installed, reachable)
- `haproxy` VM (OS installed, reachable)
- `nfs` VM (OS installed, reachable) when `storage_backend: nfs`
- ESXi hosts installed
- Network plan fixed (subnet, VIPs, gateway, DNS IP)
- Correct `inventory.ini` group mapping (`dns`, `haproxy`, `infra`, `rhel`)
- CoreOS template already imported in vCenter
- Required secrets available (pull secret, vSphere credentials, optional AD/vCenter secrets)

## 1B. Inventory & Vars Mapping (Minimal Example)
`inventory.ini`:
```ini
[dns]
dns ansible_host=192.168.1.8 ansible_user=root

[haproxy]
haproxy ansible_host=192.168.1.15 ansible_user=root

[infra:children]
dns
haproxy

[rhel:children]
dns
haproxy
```

`group_vars/all.yml` (minimal shape):
```yaml
network:
  domain: "lab.local"

okd:
  cluster_name: "okd"

infrastructure:
  load_balancer_vips:
    - ip: "192.168.1.50"
      name: "api.okd.lab.local"
    - ip: "192.168.1.51"
      name: "apps.okd.lab.local"
```

## 2. Purpose
Flow Summary:
```text
Ansible (Infra + Ignition)
        ->
Terraform (VM Provisioning)
        ->
Bootstrap Phase
        ->
Post-Bootstrap HAProxy Cleanup
        ->
Cluster Converges
```

This project automates OKD UPI preparation on vSphere for:
- OKD `4.18.0-okd-scos.10`
- `platform: none`
- `3 masters + 1 worker`

Automation split:
- Ansible: infra services + OKD ignition artifact generation
- Terraform: VM creation in vSphere + ignition injection via `guestinfo.*`

## 2A. Scope Boundaries
Supported scope:
- vSphere-based OKD UPI flow
- single-network lab assumptions as defined in vars/topology sections
- IPv4, non-disconnected install pattern

Not supported yet in this repo flow:
- multi-VLAN/multi-network automation logic
- IPv6-only installs
- proxy/disconnected registry full automation
- generic cloud provider targets outside vSphere

## 2B. Assumptions
- You already understand vSphere, DNS, HAProxy VIP behavior, and Linux operations.
- DNS and HAProxy hosts exist and are reachable before running core infra playbooks.
- DNS used by this flow is authoritative for the cluster domain.
- A matching CoreOS OVA has already been imported and converted to a vCenter template.
- `inventory.ini` groups map correctly to real hosts.
- Control host has network access to DNS/HAProxy/vCenter and has required binaries installed.

## 3. Topology (Expected)
- DNS: `192.168.1.8`
- HAProxy: `192.168.1.15`
- API/API-INT VIP: `192.168.1.50`
- Ingress VIP: `192.168.1.51`
- bootstrap: `192.168.1.30`
- masters: `.31 .32 .33`
- worker: `.34`

Lab baseline:
- 2 ESXi hosts
- datastore: NFS (default), vSAN (optional)
- per ESXi host: `52 GB RAM`, `12 vCPU`
- vMotion enabled
- DRS enabled

If you use more than 2 ESXi hosts:
- add them in `infrastructure.esxi` vars
- ensure DNS records include those additional ESXi hosts

## 4. Required Variables
Edit `group_vars/all.yml` and set at least:
- `okd.ssh_public_key`
- `okd.pull_secret`

If using platform roles:
- `ad_admin_user`, `ad_admin_password`
- `vcenter_password`, `esxi_password`
- `infrastructure.vcenter.vcsa_ova_file`
- `infrastructure.ansible_server.ansible_admin_ssh_key`

Secrets policy:
- do not commit secrets to git
- keep secrets in vault/secret files
- for Terraform secret use env var:
```bash
export TF_VAR_vsphere_password='YOUR_REAL_PASSWORD'
```

## 5. Execution Flow
### 5.1 Infra
Run:
```bash
ansible-playbook playbooks/01_core_infra.yml
```
Note: `playbooks/01_core_infra.yml` is idempotent and can be re-run safely.
Prerequisite:
- `dns` and `haproxy` hosts must already exist in inventory and be reachable (OS installed).
- They do **not** need to be pre-configured; `01_core_infra.yml` configures DNS and HAProxy.

Optional (vCenter-only, separate flow):
```bash
ansible-playbook playbooks/00_platform_roles.yml
```
Note:
- If you use `storage_backend: nfs`, `00_platform_roles.yml` now also includes a pre-vCenter `nfs` block (`firewall_conf` + `lvm_create` + `nfs_conf` based on toggles).
- If you deploy vCenter itself on NFS, do a pre-mount of that NFS datastore on standalone ESXi first; `vcenter_create_nfs_datastore` runs only after vCenter exists.
- Set `infrastructure.vcenter.deploy_storage_type` to match your bootstrap plan:
  - `local_esxi` (default)
  - `nfs_pre_mounted` (requires pre-mounted NFS datastore on standalone ESXi)

### 5.2 OKD Prep
Run:
```bash
ansible-playbook playbooks/02_okd_upi_prepare.yml
```

Notes:
- Generates `bootstrap.64`, `master.64`, `worker.64` in `okd.install_dir`.
- Also installs global symlinks:
  - `/usr/local/bin/oc`
  - `/usr/local/bin/kubectl`
  - `/usr/local/bin/openshift-install`

### 5.3 Terraform
Run from `terraform/`:
```bash
terraform init
terraform plan
terraform apply
```

Terraform reminders:
- `file(...)` reads files from the machine running Terraform.
- If ignitions are in `/root/okd-install`, run Terraform on that host (or copy files locally).
- Do not run Terraform from another host unless ignition paths in `terraform.tfvars` are valid on that host.
- Before `terraform apply`, the correct CoreOS (FCOS/SCOS) OVA for your target OKD version must already be downloaded and imported into vCenter as a VM template.
- `template_name` in `terraform/terraform.tfvars` must match that existing vCenter template.
- VM disks clone from template disk 0.
- Power-on sequencing delay uses `bootstrap_to_nodes_delay_seconds`.

Template details checklist:
- use the OVA that matches your target OKD release stream (SCOS/FCOS as required by your chosen release)
- convert imported VM to template in vCenter
- ensure template firmware/guest settings are compatible with your cluster plan
- keep `template_name` exact in `terraform/terraform.tfvars`
- static MACs are used in this project to align with DHCP reservations

### 5.4 Bootstrap Phase
Monitor bootstrap:
```bash
/root/okd-tools/openshift-install --dir /root/okd-install wait-for bootstrap-complete --log-level=debug
```

### 5.5 Post Bootstrap
Run:
```bash
ansible-playbook playbooks/03_post_bootstrap_haproxy.yml
```

What this playbook does:
- removes bootstrap backend lines from HAProxy (supports both `bootstrap` and `bootstrap.okd.lab.local` formats)
- reloads HAProxy
- removes stale `known_hosts` entries only for bootstrap/master/worker hosts
- auto-approves pending CSRs in a limited retry window (lab helper)

Production note:
- CSR auto-approve helper is for lab speed only and should be disabled in production clusters.

Toggles:
```bash
ansible-playbook -i inventory.ini playbooks/03_post_bootstrap_haproxy.yml -e ssh_known_hosts_cleanup_enabled=false
ansible-playbook -i inventory.ini playbooks/03_post_bootstrap_haproxy.yml -e csr_auto_approve_enabled=false
```

### 5.6 Install Monitoring
Monitor full install:
```bash
/root/okd-tools/openshift-install --dir /root/okd-install wait-for install-complete --log-level=debug
```

Cluster checks:
```bash
export KUBECONFIG=/root/okd-install/auth/kubeconfig
oc get nodes -o wide
oc get clusteroperators
oc get clusterversion
oc get mcp
oc get csr
```

## 6. Terraform Install
### RHEL / Rocky / AlmaLinux
```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo dnf makecache
sudo dnf install -y terraform
terraform -version
```

If repo install fails:
```bash
cd /tmp
curl -LO https://releases.hashicorp.com/terraform/1.11.1/terraform_1.11.1_linux_amd64.zip
sudo dnf install -y unzip
unzip terraform_1.11.1_linux_amd64.zip
sudo install -m 0755 terraform /usr/local/bin/terraform
terraform -version
```

### Ubuntu / Debian
```bash
sudo apt-get update
sudo apt-get install -y gpg software-properties-common curl
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y terraform
terraform -version
```

## 7. Terraform Configuration
Main files:
- `terraform/main.tf`
- `terraform/terraform.tfvars`

Set in `terraform/terraform.tfvars`:
- `vsphere_user`, `vsphere_server`
- `datacenter`, `cluster`, `datastore`, `network`, `template_name`
- `bootstrap_mac_address`
- `bootstrap_ignition_b64_file`, `master_ignition_b64_file`, `worker_ignition_b64_file`
- node MACs in `masters[]` and `workers[]`

Example ignition paths:
```hcl
bootstrap_ignition_b64_file = "/root/okd-install/bootstrap.64"
master_ignition_b64_file    = "/root/okd-install/master.64"
worker_ignition_b64_file    = "/root/okd-install/worker.64"
```

Example memory (12GB):
```hcl
bootstrap_memory_mb = 12288
master_memory_mb    = 12288
worker_memory_mb    = 12288
```

Terraform hygiene:
- always run `terraform validate` and `terraform plan` before `apply`
- keep state consistent and avoid manual VM edits outside Terraform
- for team use, prefer remote state backend with locking (if available in your environment)

## 8. Done State
Installation is considered successful when:
- `oc get nodes` shows all expected nodes `Ready`
- all ClusterOperators are `Available=True` and `Degraded=False`
- bootstrap VM is powered off/removed from runtime use
- bootstrap backend entries are removed from HAProxy
- `playbooks/05_post_install_validation.yml` report status is `PASS`

## 8A. Post-Install Validation Report
Run:
```bash
ansible-playbook -i inventory.ini playbooks/05_post_install_validation.yml
```

Optional overrides:
```bash
ansible-playbook -i inventory.ini playbooks/05_post_install_validation.yml \
  -e validation_kubeconfig=/root/okd-install/auth/kubeconfig \
  -e validation_oc_bin=/usr/local/bin/oc \
  -e validation_output_dir=./reports
```

Generated files:
- `reports/post-install-validation-latest.json`
- `reports/post-install-validation-latest.md`
- timestamped report copies in the same folder

## 8B. Pre-Install OKD Validation Report
Run before Terraform/installer waits:
```bash
ansible-playbook -i inventory.ini playbooks/07_pre_install_okd.yml
```
Strict mode (fail on blockers):
```bash
ansible-playbook -i inventory.ini playbooks/07_pre_install_okd.yml -e preokd_fail_on_critical=true
```

Strict mode before `terraform apply`:
```bash
ansible-playbook -i inventory.ini playbooks/07_pre_install_okd.yml -e preokd_require_ignition_files=true
```

This validates and reports:
- OKD critical vars (`cluster_name`, `base_domain`, `version`, `ssh_public_key`, `pull_secret`)
- `openshift-install` and `oc` binary presence
- DNS resolution of `api`, `api-int`, and console route host
- Terraform file presence and `template_name` in `terraform.tfvars`
- ignition file presence in install dir and ignition paths from `terraform.tfvars` (strict mode)

Reports:
- `reports/pre-install-okd-latest.json`
- `reports/pre-install-okd-latest.md`

## 9. Common Failure Causes
- wrong/missing `template_name`
- wrong ignition file paths in `terraform.tfvars`
- running Terraform on a host that cannot read ignition files
- no network access from control host to vCenter
- `api-int` DNS not pinned to final VIP from start
- pending CSRs not approved (worker never joins, ingress stays degraded)

## 10. Troubleshooting First Checks
If `wait-for bootstrap-complete` hangs:
1. Validate DNS first:
```bash
dig +short api.okd.lab.local @192.168.1.8
dig +short api-int.okd.lab.local @192.168.1.8
```
2. Validate HAProxy listeners:
```bash
ss -lntp | egrep '6443|22623|80|443'
```
3. Check installer progress logs:
```bash
tail -n 200 /root/okd-install/.openshift_install.log
```
4. Check pending CSRs:
```bash
export KUBECONFIG=/root/okd-install/auth/kubeconfig
oc get csr
```

## 10A. Failure Recovery Matrix
| Scenario | Recommended action |
|---|---|
| Bootstrap wait stuck | Check DNS resolution and HAProxy backends/listeners first, then installer log |
| Wrong/missing ignition content | Re-run `playbooks/02_okd_upi_prepare.yml`, verify `.64` files, then `terraform apply` |
| Worker does not join (CSR pending) | Review `oc get csr`, approve required CSRs (or use lab auto-approve helper) |
| Need full clean rebuild | `openshift-install destroy cluster --dir /root/okd-install` then `terraform destroy`, regenerate, re-apply |

## 11. Implementation FAQ (OKD + Terraform)
### 11.1 Which CoreOS OVA should I use?
- Use the OVA that matches the exact OKD release you target.
- For this project baseline (`4.18.0-okd-scos.10`), use the corresponding SCOS stream artifact for VMware.
- Import OVA into vCenter and convert it to a VM template.
- Set `template_name` in `terraform/terraform.tfvars` to that exact template name.

Find the correct artifact from scratch (example for `4.18.0-okd-scos.10`):
```bash
cd /root/okd-install
export OKD_VERSION=4.18.0-okd-scos.10

# download openshift-install
curl -L \
  https://github.com/okd-project/okd/releases/download/$OKD_VERSION/openshift-install-linux-$OKD_VERSION.tar.gz \
  -o openshift-install.tar.gz
tar zxf openshift-install.tar.gz
chmod +x openshift-install

# generate stream metadata
./openshift-install coreos print-stream-json > stream.json

# get VMware OVA URL for this OKD release stream
jq -r '.architectures.x86_64.artifacts.vmware.formats.ova.disk.location' stream.json

# optional: download OVA
curl -L "$(jq -r '.architectures.x86_64.artifacts.vmware.formats.ova.disk.location' stream.json)" -o coreos-vmware.ova

# inspect disk metadata structure (url/checksum fields)
jq '.architectures.x86_64.artifacts.vmware.formats.ova.disk' stream.json

# verify checksum when sha256 exists in stream metadata
OVA_SHA="$(jq -r '.architectures.x86_64.artifacts.vmware.formats.ova.disk.sha256 // empty' stream.json)"
[ -n "$OVA_SHA" ] && echo "${OVA_SHA}  coreos-vmware.ova" | sha256sum -c -
```

### 11.2 Template settings checklist
- Template must be bootable/usable for your target release stream.
- Keep consistent firmware/network adapter choices across all node clones.
- `disk.EnableUUID` and `stealclock.enable` are applied at VM level by Terraform.

### 11.3 DHCP vs static MAC behavior
- This repo uses static MACs to match DHCP reservations.
- If you do not use DHCP reservations, you can adapt Terraform to use generated MACs and static guest networking strategy.
- If MACs are not pinned while DHCP reservations are expected, nodes may receive wrong addresses and bootstrap can fail.

### 11.4 Canonical binary paths (`/root/okd-tools` vs `/usr/local/bin`)
- Source binaries are managed in `okd.tools_dir` (default `/root/okd-tools`).
- Role also creates global symlinks in `/usr/local/bin`.
- Recommended command style in operations docs uses explicit full paths for deterministic execution.

### 11.5 Re-run semantics
- `01_core_infra.yml` is idempotent and safe to re-run.
- `02_okd_upi_prepare.yml` may re-render `install-config.yaml` and regenerate artifacts in install dir.
- For a fully clean OKD regenerate cycle, remove/backup old install dir before re-running `02`.
- Terraform behavior depends on state and diffs; changes in key VM attributes can trigger recreate.

### 11.7 Safe re-run policy
- Safe to re-run:
- `playbooks/06_pre_install_infra.yml`
- `playbooks/01_core_infra.yml`
- `playbooks/03_post_bootstrap_haproxy.yml`
- Conditionally safe:
- `playbooks/02_okd_upi_prepare.yml` (re-generates artifacts; confirm install dir intent before re-run)
- Requires explicit lifecycle decision:
- Terraform changes that affect VM identity/network may recreate resources
- Cleanup operations when rebuilding from scratch:
- `openshift-install destroy cluster --dir /root/okd-install` (when cluster exists)
- `terraform destroy` (if Terraform-managed VMs must be fully re-created)

### 11.6 Bootstrap VM lifecycle
- After `bootstrap-complete` and successful post-bootstrap HAProxy cleanup, bootstrap VM is no longer needed for steady state.
- Keep it powered off (or remove it per your lab policy).
- Before removal, keep useful logs/artifacts from `/root/okd-install/.openshift_install.log` for troubleshooting history.

## 12. Known Limitations
- Single-network lab model is the default and validated path.
- No full disconnected/proxy automation in this repo.
- No machine-api based worker lifecycle automation in this UPI flow.
- DHCP reservation model is assumed when static MACs are used.
- Terraform backend/locking is local unless you explicitly configure a remote backend.

## 13. Future Improvements
- Add optional Terraform module to provision HAProxy VM after vCenter bootstrap.
- Add multi-network and VLAN-aware inventory/vars patterns.
- Add optional disconnected/proxy install profiles.
- Add stricter preflight checks for OVA/template compatibility and DNS reverse integrity.

## 14. Storage Backend Choice (NFS Default, vSAN Optional)
- For this repo, `nfs` is the practical default backend (`storage_backend: nfs`) because it works better for small labs (1-2 ESXi) without vSAN witness/licensing complexity.
- `vsan` remains supported as an optional path for environments that explicitly want vSAN workflow and can satisfy disk-group requirements.
- For nested vSAN labs, use explicit disk-group discipline (`30 GB boot`, `20 GB cache SSD-marked`, `2x100 GB capacity`) and keep auto-claim disabled.
- Switching backend is explicit via `storage_backend` and matching role toggles:
  - NFS path: `storage_backend: nfs` + `platform_roles.vcenter_create_nfs_datastore_enabled=true`
  - vSAN path: `storage_backend: vsan` + `platform_roles.vcenter_create_vsan_datastore_enabled=true`
- Changing `storage_backend` after initial infra converge is a rebuild scenario, not an in-place migration path.
- Prerequisites:
  - NFS: pre-existing NFS host OS, reachable from ESXi/vCenter, exported path configured
  - vSAN: proper vSAN license/capability, valid vmkernel networking, explicit disk-group mapping
- vCenter-on-NFS note:
  - initial vCenter deployment cannot rely on `vcenter_create_nfs_datastore` because that role needs vCenter already running
  - for that case, pre-mount NFS datastore on standalone ESXi, deploy vCenter there, then continue automation

Decision matrix:
| Scenario | Recommended backend |
|---|---|
| 1 ESXi host lab | `nfs` |
| 2 ESXi lab (no witness / no vSAN license plan) | `nfs` |
| 2+ ESXi with complete vSAN design | `vsan` |
| Nested environment with unstable SSD marking | `nfs` |

Important:
- vSAN vmkernel creation is backend-aware: if `storage_backend` is not `vsan`, vSAN vmkernel tasks are skipped.


