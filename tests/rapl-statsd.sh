#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$ROOT_DIR/host/netdata-rapl-statsd"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/intel-rapl/intel-rapl:0"
printf '%s\n' 10000000 > "$TEST_ROOT/intel-rapl/intel-rapl:0/max_energy_range_uj"
printf '%s\n' 1000000 > "$TEST_ROOT/intel-rapl/intel-rapl:0/energy_uj"
export RAPL_ROOT="$TEST_ROOT"
export STATSD_OUTPUT="$TEST_ROOT/statsd.out"

[[ "$(find_zone)" == "$TEST_ROOT/intel-rapl/intel-rapl:0" ]]
emit_gauge 12.345
grep -Fqx 'netdata.rapl.package_watts:12.345|g' "$STATSD_OUTPUT"

watts="$(calculate_watts 1000000 2000000 1 10000000)"
[[ "$watts" == "1.000" ]]

wrapped_watts="$(calculate_watts 9500000 500000 1 10000000)"
[[ "$wrapped_watts" == "1.000" ]]

printf '%s\n' 'rapl-statsd tests passed'
