#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
json_output="$(bash "$ROOT_DIR/scripts/preflight.sh" --json)"

fake_sysfs="$(mktemp -d)"
trap 'rm -rf "$fake_sysfs"' EXIT
mkdir -p "$fake_sysfs/devices/virtual/powercap" \
    "$fake_sysfs/class/hwmon/hwmon0" \
    "$fake_sysfs/class/nvme/nvme0"
printf '%s\n' 'preflight-test-hwmon' > "$fake_sysfs/class/hwmon/hwmon0/name"
printf '%s\n' 'preflight-test-nvme' > "$fake_sysfs/class/nvme/nvme0/model"
output="$(SYSFS_ROOT="$fake_sysfs" bash "$ROOT_DIR/scripts/preflight.sh")"
grep -Fq 'preflight: powercap entries:' <<< "$output"
grep -Fq 'preflight-test-hwmon' <<< "$output"
grep -Fq 'preflight-test-nvme' <<< "$output"

grep -Eq '^\{.*"docker_available":(true|false),.*\}$' <<< "$json_output"
grep -Eq '"compose_available":(true|false)' <<< "$json_output"
grep -Eq '"rapl_path":(true|false)' <<< "$json_output"
grep -Eq '"hwmon_path":(true|false)' <<< "$json_output"
grep -Eq '"nvme_path":(true|false)' <<< "$json_output"
grep -Eq '"native_cloudflared":(true|false)' <<< "$json_output"

printf '%s\n' 'preflight tests passed'
