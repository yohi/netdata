#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$(bash "$ROOT_DIR/scripts/preflight.sh" --json)"

grep -Eq '^\{.*"docker_available":(true|false),.*\}$' <<< "$output"
grep -Eq '"compose_available":(true|false)' <<< "$output"
grep -Eq '"rapl_path":(true|false)' <<< "$output"
grep -Eq '"hwmon_path":(true|false)' <<< "$output"
grep -Eq '"nvme_path":(true|false)' <<< "$output"
grep -Eq '"native_cloudflared":(true|false)' <<< "$output"

printf '%s\n' 'preflight tests passed'
