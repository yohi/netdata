#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_ROOT="${NETDATA_RUNTIME_ROOT:-$ROOT_DIR}"

die() {
    printf 'render-config: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf 'Usage: %s parent|child\n' "${0##*/}" >&2
    exit 2
}

require_value() {
    local name="$1"
    [[ -n "${!name:-}" ]] || die "$name is required"
}

valid_ipv4() {
    local value="$1" octet
    local -a octets
    [[ "$value" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -r -a octets <<< "$value"
    for octet in "${octets[@]}"; do
        ((10#$octet <= 255)) || return 1
    done
}

validate_key() {
    local key_file="$1" key line_count
    [[ -f "$key_file" && ! -L "$key_file" ]] || die 'STREAM_API_KEY_FILE must be a regular file'
    [[ -r "$key_file" ]] || die 'STREAM_API_KEY_FILE is not readable'

    key="$(<"$key_file")"
    line_count="$(wc -l < "$key_file")"
    ((line_count <= 1)) || die 'stream API key file contains multiple lines'
    [[ "$key" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || die 'stream API key must be a UUID'
    [[ ! "$key" =~ [[:space:]] ]] || die 'stream API key contains whitespace'
    STREAM_API_KEY="$key"
}

render_template() {
    local template="$1" output="$2" content temp
    content="$(<"$template")"
    content="${content//__NETDATA_HOSTNAME__/$NETDATA_HOSTNAME}"
    content="${content//__PARENT_LAN_IP__/$PARENT_LAN_IP}"
    content="${content//__GATEWAY_LAN_IP__/$GATEWAY_LAN_IP}"
    content="${content//__STREAM_API_KEY__/$STREAM_API_KEY}"

    temp="$(mktemp "${output}.tmp.XXXXXX")"
    chmod 600 "$temp"
    printf '%s\n' "$content" > "$temp"
    mv -f "$temp" "$output"
}

[[ $# -eq 1 ]] || usage
role="$1"
[[ "$role" == parent || "$role" == child ]] || usage

require_value NETDATA_HOSTNAME
require_value PARENT_LAN_IP
require_value STREAM_API_KEY_FILE
[[ "$NETDATA_HOSTNAME" =~ ^[A-Za-z0-9._-]+$ ]] || die 'NETDATA_HOSTNAME contains unsupported characters'
valid_ipv4 "$PARENT_LAN_IP" || die 'PARENT_LAN_IP must be an IPv4 address'
validate_key "$STREAM_API_KEY_FILE"

GATEWAY_LAN_IP="${GATEWAY_LAN_IP:-}"
if [[ "$role" == parent ]]; then
    [[ -n "$GATEWAY_LAN_IP" ]] || die 'GATEWAY_LAN_IP is required for parent'
    valid_ipv4 "$GATEWAY_LAN_IP" || die 'GATEWAY_LAN_IP must be an IPv4 address'
fi

runtime_dir="$RUNTIME_ROOT/$role"
mkdir -p "$runtime_dir"
chmod 700 "$runtime_dir"
render_template "$ROOT_DIR/$role/config/netdata.conf.tmpl" "$runtime_dir/netdata.conf"
render_template "$ROOT_DIR/$role/config/stream.conf.tmpl" "$runtime_dir/stream.conf"
chmod 600 "$runtime_dir/netdata.conf" "$runtime_dir/stream.conf"
printf 'render-config: generated %s runtime config\n' "$role"
