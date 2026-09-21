#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export NETDATA_HOSTNAME=ai-agent-test
export PARENT_LAN_IP=192.0.2.10
export GATEWAY_LAN_IP=192.0.2.20
export STREAM_API_KEY_FILE="$TEST_ROOT/stream-api-key"
export NETDATA_RUNTIME_ROOT="$TEST_ROOT/runtime"
printf '%s\n' '11111111-2222-3333-4444-555555555555' > "$STREAM_API_KEY_FILE"
chmod 600 "$STREAM_API_KEY_FILE"

if ! bash "$ROOT_DIR/scripts/render-config.sh" parent; then
    printf '%s\n' 'parent config rendering failed' >&2
    exit 1
fi

parent_netdata="$NETDATA_RUNTIME_ROOT/parent/netdata.conf"
parent_stream="$NETDATA_RUNTIME_ROOT/parent/stream.conf"
grep -Fq 'hostname = ai-agent-test' "$parent_netdata"
grep -Fq '192.0.2.10:19999=dashboard 192.0.2.10:19998=streaming' "$parent_netdata"
grep -Fq '[11111111-2222-3333-4444-555555555555]' "$parent_stream"
grep -Fq 'allow from = 192.0.2.20' "$parent_stream"

if ! bash "$ROOT_DIR/scripts/render-config.sh" child; then
    printf '%s\n' 'child config rendering failed' >&2
    exit 1
fi

child_netdata="$NETDATA_RUNTIME_ROOT/child/netdata.conf"
child_stream="$NETDATA_RUNTIME_ROOT/child/stream.conf"
grep -Fq 'hostname = ai-agent-test' "$child_netdata"
grep -Fq 'mode = none' "$child_netdata"
grep -Fq 'destination = 192.0.2.10:19998' "$child_stream"
grep -Fq 'api key = 11111111-2222-3333-4444-555555555555' "$child_stream"

unset NETDATA_RUNTIME_ROOT
default_runtime="$TEST_ROOT/default-runtime"
NETDATA_RUNTIME_ROOT="$default_runtime" bash "$ROOT_DIR/scripts/render-config.sh" parent
test -f "$default_runtime/parent/netdata.conf"
test -f "$default_runtime/parent/stream.conf"

chmod 400 "$STREAM_API_KEY_FILE"
readonly_runtime="$TEST_ROOT/readonly-runtime"
if ! NETDATA_RUNTIME_ROOT="$readonly_runtime" bash "$ROOT_DIR/scripts/render-config.sh" parent >/dev/null; then
    printf '%s\n' 'owner-readable API key file was rejected' >&2
    exit 1
fi

chmod 200 "$STREAM_API_KEY_FILE"
owner_unreadable_runtime="$TEST_ROOT/owner-unreadable-runtime"
if NETDATA_RUNTIME_ROOT="$owner_unreadable_runtime" bash "$ROOT_DIR/scripts/render-config.sh" parent >/dev/null 2>&1; then
    printf '%s\n' 'owner-unreadable API key file was accepted' >&2
    exit 1
fi

chmod 644 "$STREAM_API_KEY_FILE"
insecure_runtime="$TEST_ROOT/insecure-runtime"
if NETDATA_RUNTIME_ROOT="$insecure_runtime" bash "$ROOT_DIR/scripts/render-config.sh" parent >/dev/null 2>&1; then
    printf '%s\n' 'insecure API key file permissions were accepted' >&2
    exit 1
fi
test ! -e "$insecure_runtime/parent/netdata.conf"
test ! -e "$insecure_runtime/parent/stream.conf"

chmod 600 "$STREAM_API_KEY_FILE"
rm -f "$STREAM_API_KEY_FILE"
missing_runtime="$TEST_ROOT/missing-runtime"
if NETDATA_RUNTIME_ROOT="$missing_runtime" bash "$ROOT_DIR/scripts/render-config.sh" parent; then
    printf '%s\n' 'missing API key file was accepted' >&2
    exit 1
fi
test ! -e "$missing_runtime/parent/netdata.conf"
test ! -e "$missing_runtime/parent/stream.conf"

printf '%s\n' 'render-config tests passed'
