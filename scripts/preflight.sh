#!/usr/bin/env bash
set -euo pipefail

json=false
if [[ $# -gt 1 ]]; then
    printf 'Usage: %s [--json]\n' "${0##*/}" >&2
    exit 2
fi
if [[ ${1:-} == --json ]]; then
    json=true
elif [[ $# -eq 1 ]]; then
    printf 'Usage: %s [--json]\n' "${0##*/}" >&2
    exit 2
fi
sysfs_root="${SYSFS_ROOT:-/sys}"

has_command() {
    command -v "$1" >/dev/null 2>&1
}

path_exists() {
    [[ -d "$1" ]]
}

docker_available=false
compose_available=false
native_netdata=false
native_cloudflared=false
cloudflare_cli_access=false
rapl_path=false
hwmon_path=false
nvme_path=false

has_command docker && docker_available=true
if has_command docker && docker compose version >/dev/null 2>&1; then
    compose_available=true
fi
if dpkg-query -W -f='${Status}' netdata 2>/dev/null | grep -q 'install ok installed'; then
    native_netdata=true
fi
if dpkg-query -W -f='${Status}' cloudflared 2>/dev/null | grep -q 'install ok installed'; then
    native_cloudflared=true
fi
path_exists "$sysfs_root/devices/virtual/powercap" && rapl_path=true
path_exists "$sysfs_root/class/hwmon" && hwmon_path=true
path_exists "$sysfs_root/class/nvme" && nvme_path=true
if has_command cloudflared && cloudflared tunnel list >/dev/null 2>&1; then
    cloudflare_cli_access=true
fi

if "$json"; then
    printf '{"docker_available":%s,"compose_available":%s,"native_netdata":%s,"native_cloudflared":%s,"cloudflare_cli_access":%s,"rapl_path":%s,"hwmon_path":%s,"nvme_path":%s}\n' \
        "$docker_available" "$compose_available" "$native_netdata" "$native_cloudflared" "$cloudflare_cli_access" "$rapl_path" "$hwmon_path" "$nvme_path"
    exit 0
fi

printf 'preflight: hostname=%s\n' "$(hostname)"
printf 'preflight: kernel=%s\n' "$(uname -srmo)"
if has_command lsb_release; then
    printf 'preflight: os=%s\n' "$(lsb_release -ds)"
fi
printf 'preflight: docker_available=%s\n' "$docker_available"
printf 'preflight: compose_available=%s\n' "$compose_available"
printf 'preflight: native_netdata=%s (pre-existing host state only)\n' "$native_netdata"
printf 'preflight: native_cloudflared=%s (pre-existing host state only)\n' "$native_cloudflared"
printf 'preflight: cloudflare_cli_access=%s\n' "$cloudflare_cli_access"
printf 'preflight: rapl_path=%s\n' "$rapl_path"
printf 'preflight: hwmon_path=%s\n' "$hwmon_path"
printf 'preflight: nvme_path=%s\n' "$nvme_path"

if has_command ip; then
    printf '%s\n' 'preflight: interfaces:'
    ip -br addr
fi
if "$rapl_path"; then
    printf '%s\n' 'preflight: powercap entries:'
    for path in "$sysfs_root"/devices/virtual/powercap/*; do
        [[ -e "$path" ]] || continue
        printf '  %s\n' "${path##*/}"
    done
fi
if "$hwmon_path"; then
    printf '%s\n' 'preflight: hwmon names:'
    for name_file in "$sysfs_root"/class/hwmon/hwmon*/name; do
        [[ -r "$name_file" ]] || continue
        printf '  %s=%s\n' "${name_file%/name}" "$(<"$name_file")"
    done
fi
if "$nvme_path"; then
    printf '%s\n' 'preflight: NVMe models:'
    for model_file in "$sysfs_root"/class/nvme/nvme*/model; do
        [[ -r "$model_file" ]] || continue
        printf '  %s=%s\n' "${model_file%/model}" "$(<"$model_file")"
    done
fi
