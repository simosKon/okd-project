# Template Automation

This directory automates creation of:

- OKD node template from Fedora CoreOS OVA
- HAProxy template from RHEL 9.4 ISO

## Prerequisites

- `govc` installed and reachable in `PATH`
- `packer` installed (`hashicorp/packer`)
- AWX read-only MinIO credential attached to artifact download jobs
- vCenter credentials with permissions to create VM/template/folder
- The host running `packer build` must allow inbound TCP access from the installer VM network to the temporary Packer HTTP server range `8600-8610`
- For a fully automated pipeline, create the shared VM folder first with `terraform/foundation`
- Run `terraform/foundation` before Packer whenever `VM_FOLDER` or `folder` is set and you want templates to be placed there

```bash
ansible-playbook -i inventory.ini playbooks/08_sync_terraform.yml
ansible-playbook -i inventory.ini playbooks/09_terraform_foundation.yml
ansible-playbook -i inventory.ini playbooks/09_terraform_foundation.yml -e terraform_operation=apply_saved
ansible-playbook -i inventory.ini playbooks/12_sync_packer.yml
```

## 1) OKD Template (OVA -> Template)

Use the AWX wrapper, which downloads the OVA from MinIO and runs the govc script on the persistent `ansible` host:

```bash
ansible-playbook -i inventory.ini playbooks/14_build_okd_template.yml
```

If `VM_FOLDER` is set, that folder must already exist in vCenter. In this repo, `terraform/foundation` is the intended owner of that folder.

## 2) HAProxy Template (ISO -> VM -> Template)

Download the ISO from MinIO and upload it to the datastore:

```bash
ansible-playbook -i inventory.ini playbooks/15_upload_rhel_iso.yml
```

Then build with Packer:

```bash
ansible-playbook -i inventory.ini playbooks/16_build_haproxy_template.yml
```

Notes:

- `build.sh` renders `http/ks.cfg` from `http/ks.cfg.tmpl` using a one-way hash of the Vault-injected SSH password and removes it when the build exits.
- The host running `packer build` must be reachable by the guest on TCP ports `8600-8610`.
- If `firewalld` or another firewall blocks that range, the installer will fail with `failed to fetch kickstart` / `No route to host`.
- If you set `folder` in `auto.pkrvars.hcl`, that folder must already exist in vCenter. In this repo, `terraform/foundation` is the intended owner of that folder, so run it before this Packer build.

## Enterprise Pattern (Reference)

For larger environments, template automation is usually part of a full pipeline:

1. Artifact source/registry
- Store ISO/OVA inputs and track output artifacts (template versions, plans, reports).

2. Packer stage
- Build and version golden templates from ISO/OVA.

3. Terraform stage
- Provision infra/VMs using approved template versions.

4. Ansible stage
- Apply post-configuration, hardening, and service setup.

5. CI/CD orchestration
- GitLab CI / Jenkins / GitHub Actions run all stages as pipeline-as-code.
- Keep full execution history (who/when/what), logs, artifacts, and approval gates.
