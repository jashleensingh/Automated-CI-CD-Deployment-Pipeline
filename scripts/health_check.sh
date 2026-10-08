#!/usr/bin/env bash
# Usage: health_check.sh <port> [retries] [delay_seconds]
# Exits 0 the first time GET /health returns 200, 1 if it never does
# within the retry budget. Retrying matters even for "should be instant"
# process starts — the window between forking a process and it actually
# binding its listening socket is real, and treating the first failed
# check as fatal would make this pipeline flaky for no good reason.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

PORT="${1:?usage: health_check.sh <port> [retries] [delay]}"
RETRIES="${2:-$HEALTH_CHECK_RETRIES}"
DELAY="${3:-$HEALTH_CHECK_DELAY}"

for ((i = 1; i <= RETRIES; i++)); do
    if curl -sf -o /dev/null "http://127.0.0.1:${PORT}/health"; then
        log_info "Health check passed on attempt $i/$RETRIES (port $PORT)"
        exit 0
    fi
    sleep "$DELAY"
done

log_warn "Health check failed after $RETRIES attempts (port $PORT)"
exit 1
