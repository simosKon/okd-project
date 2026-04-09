#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  GOVC_URL GOVC_USERNAME GOVC_PASSWORD GOVC_INSECURE GOVC_DATACENTER
  ISO_LOCAL_PATH ISO_DATASTORE ISO_DATASTORE_PATH
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

if [[ ! -f "$ISO_LOCAL_PATH" ]]; then
  echo "ERROR: ISO_LOCAL_PATH not found: $ISO_LOCAL_PATH" >&2
  exit 1
fi

if govc datastore.ls -ds "$ISO_DATASTORE" "$ISO_DATASTORE_PATH" >/dev/null 2>&1; then
  echo "ISO already exists at datastore path: [$ISO_DATASTORE] $ISO_DATASTORE_PATH"
  echo "Skipping upload."
  exit 0
fi

echo "Uploading ISO to datastore '$ISO_DATASTORE' at '$ISO_DATASTORE_PATH'..."
govc datastore.upload -ds "$ISO_DATASTORE" "$ISO_LOCAL_PATH" "$ISO_DATASTORE_PATH"
echo "OK: uploaded ISO"
