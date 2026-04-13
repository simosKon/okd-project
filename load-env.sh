#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

env_files=(
  "$SCRIPT_DIR/terraform/vsphere-auth.env"
  "$SCRIPT_DIR/packer/okd-template/okd-template.env"
  "$SCRIPT_DIR/packer/haproxy-template/packer-auth.env"
  "$SCRIPT_DIR/packer/haproxy-template/iso-upload.env"
)

for env_file in "${env_files[@]}"; do
  if [[ ! -f "$env_file" ]]; then
    echo "ERROR: missing env file: $env_file" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$env_file"
done

echo "Loaded environment files:"
for env_file in "${env_files[@]}"; do
  echo "- $env_file"
done
