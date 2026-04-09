#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  GOVC_URL GOVC_USERNAME GOVC_PASSWORD GOVC_INSECURE GOVC_DATACENTER
  DATASTORE NETWORK_NAME OVA_LOCAL_PATH IMPORT_VM_NAME TEMPLATE_NAME
)

for v in "${required_vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "ERROR: missing required env var: $v" >&2
    exit 1
  fi
done

if ! command -v govc >/dev/null 2>&1; then
  echo "ERROR: govc is not installed/in PATH" >&2
  exit 1
fi

if [[ ! -f "$OVA_LOCAL_PATH" ]]; then
  echo "ERROR: OVA_LOCAL_PATH not found: $OVA_LOCAL_PATH" >&2
  exit 1
fi

echo "Checking existing template: $TEMPLATE_NAME"
if govc find "/${GOVC_DATACENTER}" -type m -name "$TEMPLATE_NAME" | grep -q .; then
  echo "Template '$TEMPLATE_NAME' already exists. Skipping."
  exit 0
fi

if [[ -n "${VM_FOLDER:-}" ]]; then
  folder_path="/${GOVC_DATACENTER}/vm/${VM_FOLDER}"
  if ! govc folder.info "$folder_path" >/dev/null 2>&1; then
    echo "Creating VM folder: $folder_path"
    govc folder.create "$folder_path"
  fi
fi

echo "Cleaning old import VM if present: $IMPORT_VM_NAME"
govc vm.destroy "$IMPORT_VM_NAME" >/dev/null 2>&1 || true

echo "Importing OVA -> VM: $IMPORT_VM_NAME"
if [[ -n "${VM_FOLDER:-}" ]]; then
  govc import.ova \
    -name "$IMPORT_VM_NAME" \
    -ds "$DATASTORE" \
    -net "$NETWORK_NAME" \
    -folder "$VM_FOLDER" \
    "$OVA_LOCAL_PATH"
else
  govc import.ova \
    -name "$IMPORT_VM_NAME" \
    -ds "$DATASTORE" \
    -net "$NETWORK_NAME" \
    "$OVA_LOCAL_PATH"
fi

echo "Renaming import VM to template target name: $TEMPLATE_NAME"
govc vm.change -vm "$IMPORT_VM_NAME" -name "$TEMPLATE_NAME"

echo "Mark as template: $TEMPLATE_NAME"
govc vm.markastemplate "$TEMPLATE_NAME"

echo "OK: created template '$TEMPLATE_NAME' from OVA '$OVA_LOCAL_PATH'"

