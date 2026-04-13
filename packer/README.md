# Template Automation

This directory automates creation of:

- OKD node template from Fedora CoreOS OVA
- HAProxy template from RHEL 9.4 ISO

## Prerequisites

- `govc` installed and reachable in `PATH`
- `packer` installed (`hashicorp/packer`)
- vCenter credentials with permissions to create VM/template/folder
- The host running `packer build` must allow inbound TCP access from the installer VM network to the temporary Packer HTTP server range `8600-8610`
- For a fully automated pipeline, create the shared VM folder first with `terraform/foundation`
- Run `terraform/foundation` before Packer whenever `VM_FOLDER` or `folder` is set and you want templates to be placed there

```bash
cd terraform/foundation
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
terraform init
terraform apply
```

## 1) OKD Template (OVA -> Template)

Use the govc script:

```bash
cd packer/okd-template
cp okd-template.env.example okd-template.env
# edit okd-template.env
source okd-template.env
bash build_ova_template.sh
```

If `VM_FOLDER` is set in `okd-template.env`, that folder must already exist in vCenter. In this repo, `terraform/foundation` is the intended owner of that folder.

## 2) HAProxy Template (ISO -> VM -> Template)

First upload ISO to datastore:

```bash
cd packer/haproxy-template
cp iso-upload.env.example iso-upload.env
# edit iso-upload.env
source iso-upload.env
bash upload_iso.sh
```

Then build with Packer:

```bash
cp example.auto.pkrvars.hcl auto.pkrvars.hcl
# edit auto.pkrvars.hcl
packer init .
packer validate -var-file=auto.pkrvars.hcl .
packer build -var-file=auto.pkrvars.hcl .
```

Notes:

- The RHEL unattended install fetches `http/ks.cfg` from the temporary Packer HTTP server.
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
