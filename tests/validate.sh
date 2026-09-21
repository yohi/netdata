#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

copy_fixture() {
    local destination="$1"
    mkdir -p "$destination"
    cp -a "$ROOT_DIR/parent" "$ROOT_DIR/child" "$ROOT_DIR/scripts" "$destination/"
    rm -f "$destination/parent/images.env" "$destination/child/images.env"
    rm -f "$destination"/parent/runtime/*.conf "$destination"/child/runtime/*.conf
}

if ! bash "$ROOT_DIR/scripts/validate.sh" --examples; then
    printf '%s\n' 'example validation failed' >&2
    exit 1
fi

missing_deployment_root="$TEST_ROOT/missing-deployment"
copy_fixture "$missing_deployment_root"
if VALIDATE_ROOT="$missing_deployment_root" bash "$ROOT_DIR/scripts/validate.sh" --deployment; then
    printf '%s\n' 'deployment validation passed without images.env' >&2
    exit 1
fi

if ! grep -Eq 'netdatacli[[:space:]]+ping' "$ROOT_DIR/child/compose.yaml"; then
    printf '%s\n' 'child healthcheck must use netdatacli ping when Web UI is disabled' >&2
    exit 1
fi

if ! grep -Eq 'netdatacli[[:space:]]+ping' "$ROOT_DIR/parent/compose.yaml"; then
    printf '%s\n' 'parent healthcheck must use netdatacli ping when dashboard binds to LAN' >&2
    exit 1
fi

for role in parent child; do
    tracked_secret_root="$TEST_ROOT/tracked-secret-$role"
    copy_fixture "$tracked_secret_root"
    git -C "$tracked_secret_root" init -q
    mkdir -p "$tracked_secret_root/$role/secrets"
    printf '%s\n' 'forced-tracked-test-secret' > "$tracked_secret_root/$role/secrets/stream-api-key"
    git -C "$tracked_secret_root" add -f -- "$role/secrets/stream-api-key"
    if VALIDATE_ROOT="$tracked_secret_root" bash "$ROOT_DIR/scripts/validate.sh" --examples; then
        printf 'tracked %s stream API key was accepted\n' "$role" >&2
        exit 1
    fi
done

for compose_file in "$ROOT_DIR/parent/compose.yaml" "$ROOT_DIR/child/compose.yaml"; do
    if grep -Eq '(^|[[:space:]])cloudflared([[:space:]:]|$)' "$compose_file"; then
        printf 'cloudflared service must not be defined: %s\n' "$compose_file" >&2
        exit 1
    fi
done

invalid_digest_root="$TEST_ROOT/invalid-digest"
copy_fixture "$invalid_digest_root"
sed -i 's/^NETDATA_IMAGE=.*/NETDATA_IMAGE=invalid/' "$invalid_digest_root/parent/images.env.example"
if VALIDATE_ROOT="$invalid_digest_root" bash "$ROOT_DIR/scripts/validate.sh" --examples; then
    printf '%s\n' 'invalid image digest was accepted' >&2
    exit 1
fi

invalid_placeholder_root="$TEST_ROOT/invalid-placeholder"
copy_fixture "$invalid_placeholder_root"
sed -i 's/__NETDATA_HOSTNAME__/__UNKNOWN_PLACEHOLDER__/g' "$invalid_placeholder_root/parent/config/netdata.conf.tmpl"
if VALIDATE_ROOT="$invalid_placeholder_root" bash "$ROOT_DIR/scripts/validate.sh" --examples; then
    printf '%s\n' 'unresolved template placeholder was accepted' >&2
    exit 1
fi

printf '%s\n' 'validate tests passed'
