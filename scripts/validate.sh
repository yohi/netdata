#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VALIDATE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
MODE=examples
failures=0

fail() {
    printf 'validate: %s\n' "$1" >&2
    failures=$((failures + 1))
}

usage() {
    printf 'Usage: %s [--examples|--deployment]\n' "${0##*/}" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --examples)
            MODE=examples
            ;;
        --deployment)
            MODE=deployment
            ;;
        *)
            usage
            ;;
    esac
    shift
done

for script in "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/tests/*.sh; do
    [[ -f "$script" ]] || continue
    if ! bash -n "$script"; then
        fail "shell syntax: ${script#"$ROOT_DIR"/}"
    fi
    if command -v shellcheck >/dev/null 2>&1 && ! shellcheck "$script"; then
        fail "shellcheck: ${script#"$ROOT_DIR"/}"
    fi
done

read_env_value() {
    local env_file="$1" name="$2"
    awk -F= -v key="$name" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$env_file"
}

validate_image_pin() {
    local env_file="$1" name="$2"
    if ! grep -Eq "^${name}=.+@sha256:[0-9a-fA-F]{64}$" "$env_file"; then
        fail "${env_file#"$ROOT_DIR"/}: ${name} must be a digest-pinned image"
    fi
}

validate_token_file() {
    local role="$1" env_file="$2" token_path token_file mode
    token_path="$(read_env_value "$env_file" CLOUDFLARED_TOKEN_FILE)"
    [[ -n "$token_path" ]] || {
        fail "${role}/images.env: CLOUDFLARED_TOKEN_FILE is required"
        return
    }
    if [[ "$token_path" = /* ]]; then
        token_file="$token_path"
    else
        token_file="$ROOT_DIR/$role/${token_path#./}"
    fi
    [[ -f "$token_file" ]] || {
        fail "${role}: Cloudflare token file is missing"
        return
    }
    if [[ "$token_file" != *.example ]]; then
        mode="$(stat -c '%a' "$token_file")"
        [[ "$mode" == 600 ]] || fail "${role}: Cloudflare token file must be mode 600"
    fi
}

validate_runtime_configs() {
    local runtime_root key_file role config_file
    runtime_root="$(mktemp -d)"
    key_file="$runtime_root/stream-api-key"
    printf '%s\n' '11111111-2222-3333-4444-555555555555' > "$key_file"
    chmod 600 "$key_file"

    for role in parent child; do
        if ! NETDATA_HOSTNAME=validation-node \
            PARENT_LAN_IP=192.0.2.10 \
            GATEWAY_LAN_IP=192.0.2.20 \
            STREAM_API_KEY_FILE="$key_file" \
            NETDATA_RUNTIME_ROOT="$runtime_root" \
            bash "$ROOT_DIR/scripts/render-config.sh" "$role" >/dev/null; then
            fail "runtime config rendering: $role"
            continue
        fi
        for config_file in "$runtime_root/$role/netdata.conf" "$runtime_root/$role/stream.conf"; do
            [[ -s "$config_file" ]] || fail "runtime config is missing: ${config_file#"$runtime_root"/}"
            if grep -Eq '__[A-Z0-9_]+__' "$config_file"; then
                fail "unresolved template placeholder: ${config_file#"$runtime_root"/}"
            fi
            [[ "$(stat -c '%a' "$config_file")" == 600 ]] || fail "runtime config must be mode 600: ${config_file#"$runtime_root"/}"
        done
    done
    rm -rf "$runtime_root"
}

validate_compose() {
    local role env_file compose_file
    for role in parent child; do
        if [[ "$MODE" == deployment ]]; then
            env_file="$ROOT_DIR/$role/images.env"
        else
            env_file="$ROOT_DIR/$role/images.env.example"
        fi
        compose_file="$ROOT_DIR/$role/compose.yaml"
        [[ -f "$env_file" ]] || {
            fail "missing ${role}/$(basename "$env_file")"
            continue
        }
        [[ -f "$compose_file" ]] || {
            fail "missing ${role}/compose.yaml"
            continue
        }
        validate_image_pin "$env_file" NETDATA_IMAGE
        if [[ "$role" == parent ]]; then
            validate_image_pin "$env_file" CLOUDFLARED_IMAGE
            validate_token_file "$role" "$env_file"
        fi
        if ! docker compose --env-file "$env_file" -f "$compose_file" config >/dev/null; then
            fail "docker compose config: ${role}"
        fi
        if [[ "$MODE" == deployment ]]; then
            for runtime_config in "$ROOT_DIR/$role/runtime/netdata.conf" "$ROOT_DIR/$role/runtime/stream.conf"; do
                [[ -f "$runtime_config" ]] || fail "missing runtime config: ${runtime_config#"$ROOT_DIR"/}"
            done
        fi
    done
}

validate_security_invariants() {
    local compose_file
    for compose_file in "$ROOT_DIR"/parent/compose.yaml "$ROOT_DIR"/child/compose.yaml; do
        [[ -f "$compose_file" ]] || continue
        if grep -Eq 'privileged:|/var/run/docker\.sock|apparmor([=:])unconfined|^[[:space:]]+ports:' "$compose_file"; then
            fail "forbidden privilege, socket, AppArmor override, or published port: ${compose_file#"$ROOT_DIR"/}"
        fi
    done
    if [[ -f "$ROOT_DIR/child/compose.yaml" ]] && grep -q cloudflared "$ROOT_DIR/child/compose.yaml"; then
        fail 'Child Compose must not contain cloudflared'
    fi
}

validate_tracked_secrets() {
    local tracked path
    if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return
    fi
    tracked="$(git -C "$ROOT_DIR" ls-files)"
    while IFS= read -r path; do
        case "$path" in
            */stream.conf|*/cloudflared-token|*/images.env)
                fail "secret-bearing runtime file is tracked: $path"
                ;;
        esac
    done <<< "$tracked"
}

validate_runtime_configs
validate_compose
validate_security_invariants
validate_tracked_secrets

if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 && ! git -C "$ROOT_DIR" diff --check; then
    fail 'git diff --check failed'
fi

if ((failures > 0)); then
    printf 'validate: %d check(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'validate: %s checks passed\n' "$MODE"
