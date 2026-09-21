#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

if ! bash "$ROOT_DIR/scripts/validate.sh" --examples; then
    printf '%s\n' 'example validation failed' >&2
    exit 1
fi

if bash "$ROOT_DIR/scripts/validate.sh" --deployment; then
    printf '%s\n' 'deployment validation passed without images.env' >&2
    exit 1
fi

copy_fixture() {
    local destination="$1"
    mkdir -p "$destination"
    cp -a "$ROOT_DIR/parent" "$ROOT_DIR/child" "$ROOT_DIR/scripts" "$destination/"
}

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

invalid_mode_root="$TEST_ROOT/invalid-mode"
copy_fixture "$invalid_mode_root"
cp "$invalid_mode_root/parent/images.env.example" "$invalid_mode_root/parent/images.env"
cp "$invalid_mode_root/child/images.env.example" "$invalid_mode_root/child/images.env"
printf '%s\n' 'not-a-real-token' > "$invalid_mode_root/parent/secrets/cloudflared-token"
chmod 644 "$invalid_mode_root/parent/secrets/cloudflared-token"
sed -i 's#cloudflared-token.example#cloudflared-token#' "$invalid_mode_root/parent/images.env"
if VALIDATE_ROOT="$invalid_mode_root" bash "$ROOT_DIR/scripts/validate.sh" --deployment; then
    printf '%s\n' 'insecure token file mode was accepted' >&2
    exit 1
fi

printf '%s\n' 'validate tests passed'
