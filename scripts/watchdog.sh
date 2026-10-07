#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

export PATH="${HOME}/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"

if ! command -v docker >/dev/null 2>&1; then
    echo "docker command not found in PATH: $PATH" >&2
    exit 1
fi

check_and_recover() {
    local role="$1"
    local container_name="netdata-$role"
    local env_file="$ROOT_DIR/$role/images.env"
    local compose_file="$ROOT_DIR/$role/compose.yaml"

    # Skip if environment or compose file is absent on this host
    [[ -f "$env_file" && -f "$compose_file" ]] || return 0

    local is_running health_status
    if ! is_running="$(docker inspect --format='{{.State.Running}}' "$container_name" 2>/dev/null)"; then
        if [[ "$EXPLICIT_ROLE" == "true" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [$container_name] Container does not exist. Starting..."
            docker compose --env-file "$env_file" -f "$compose_file" up -d
        fi
        return 0
    fi

    health_status="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_name" 2>/dev/null || echo "none")"

    if [[ "$is_running" != "true" || "$health_status" == "unhealthy" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [$container_name] Container abnormal (running=$is_running, health=$health_status). Recovering..."
        docker compose --env-file "$env_file" -f "$compose_file" down
        docker compose --env-file "$env_file" -f "$compose_file" up -d
    fi
}

EXPLICIT_ROLE=false
if [[ $# -gt 0 ]]; then
    EXPLICIT_ROLE=true
    case "$1" in
        parent|child)
            check_and_recover "$1"
            ;;
        all)
            check_and_recover "parent"
            check_and_recover "child"
            ;;
        *)
            echo "Usage: $0 [parent|child|all]" >&2
            exit 1
            ;;
    esac
else
    # Auto-detect existing containers on this host without launching new ones
    if docker inspect netdata-parent >/dev/null 2>&1; then
        check_and_recover "parent"
    fi
    if docker inspect netdata-child >/dev/null 2>&1; then
        check_and_recover "child"
    fi
fi

