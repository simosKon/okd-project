#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_path="$script_dir/http/ks.cfg.tmpl"
kickstart_path="$script_dir/http/ks.cfg"

if [[ -z "${PKR_VAR_ssh_password:-}" ]]; then
  echo "ERROR: PKR_VAR_ssh_password must be injected by AWX." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required to generate the kickstart password hash." >&2
  exit 1
fi

password_hash="$(printf '%s' "$PKR_VAR_ssh_password" | openssl passwd -6 -stdin)"
awk -v replacement="$password_hash" '{ gsub(/__ROOT_PASSWORD_HASH__/, replacement); print }' \
  "$template_path" > "$kickstart_path"
chmod 0600 "$kickstart_path"
trap 'rm -f "$kickstart_path"' EXIT

cd "$script_dir"
packer init .
packer validate .
packer build .
