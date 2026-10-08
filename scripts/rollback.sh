#!/usr/bin/env bash
# Reverts the deploy target to the last release that passed its health
# check. Safe to call standalone (an operator running it by hand after
# noticing a problem) or automatically from deploy.sh right after a
# failed health check — both paths go through the exact same logic, so
# "automatic rollback" and "manual rollback" can never silently diverge
# in behavior.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

LAST_GOOD=$(cat "$(last_good_file)" 2>/dev/null || true)

if [[ -z "$LAST_GOOD" ]]; then
    log_error "No known-good release to roll back to. Manual intervention required."
    exit 1
fi

log_warn "Rolling back to last known-good release: $LAST_GOOD"

LAST_GOOD_DIR=$(release_dir "$LAST_GOOD")
if [[ ! -d "$LAST_GOOD_DIR" ]]; then
    log_error "Recorded known-good release '$LAST_GOOD' no longer exists on disk at $LAST_GOOD_DIR."
    exit 1
fi

# Stop whatever is currently live (the failed release), if anything.
CURRENT_LINK=$(current_link)
if [[ -L "$CURRENT_LINK" ]]; then
    stop_release "$(readlink -f "$CURRENT_LINK")"
fi

start_release "$LAST_GOOD_DIR" "$APP_PORT"

if "$SCRIPT_DIR/health_check.sh" "$APP_PORT"; then
    ln -sfn "$LAST_GOOD_DIR" "$CURRENT_LINK"
    log_info "Rollback successful — $LAST_GOOD is live again."
    exit 0
else
    log_error "Rollback target '$LAST_GOOD' itself failed its health check. This is a serious problem — the last known-good release is no longer good. Manual intervention required."
    exit 2
fi
