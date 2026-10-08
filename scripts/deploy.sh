#!/usr/bin/env bash
# Usage: deploy.sh <version> <app_source_dir> [--inject-broken]
#
# --inject-broken deliberately ships a release that fails its health
# check — it exists so the rollback path can be exercised by an actual
# failing deployment in tests (scripts/run_test_suite.sh), rather than
# only ever being tested against happy-path releases that never actually
# trigger it. A rollback script nobody has ever watched successfully
# catch a real failure isn't verified, it's hoped for.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

VERSION="${1:?usage: deploy.sh <version> <app_source_dir> [--inject-broken]}"
APP_SOURCE_DIR="${2:?usage: deploy.sh <version> <app_source_dir> [--inject-broken]}"
INJECT_BROKEN="${3:-}"

log_info "Deploying version '$VERSION'"

NEW_RELEASE_DIR=$(release_dir "$VERSION")
if [[ -d "$NEW_RELEASE_DIR" ]]; then
    log_error "Release '$VERSION' already exists at $NEW_RELEASE_DIR — versions must be unique."
    exit 1
fi

mkdir -p "$NEW_RELEASE_DIR"
cp "$APP_SOURCE_DIR/app.py" "$NEW_RELEASE_DIR/app.py"
echo "$VERSION" > "$NEW_RELEASE_DIR/VERSION"

if [[ "$INJECT_BROKEN" == "--inject-broken" ]]; then
    touch "$NEW_RELEASE_DIR/BROKEN"
    log_warn "Deliberately deploying a broken release (test mode) to exercise the rollback path."
fi

# Stop whatever's currently live BEFORE starting the new one — this
# single-port setup can't run both at once. A zero-downtime version of
# this (blue/green on two ports, switch traffic only after the new one
# is confirmed healthy) is a natural next step; see README.
CURRENT_LINK=$(current_link)
if [[ -L "$CURRENT_LINK" ]]; then
    stop_release "$(readlink -f "$CURRENT_LINK")"
fi

start_release "$NEW_RELEASE_DIR" "$APP_PORT"

if "$SCRIPT_DIR/health_check.sh" "$APP_PORT"; then
    ln -sfn "$NEW_RELEASE_DIR" "$CURRENT_LINK"
    echo "$VERSION" > "$(last_good_file)"
    log_info "Deploy of '$VERSION' succeeded and is now live."
    exit 0
fi

log_error "Deploy of '$VERSION' failed its health check. Stopping it and rolling back."
stop_release "$NEW_RELEASE_DIR"

if "$SCRIPT_DIR/rollback.sh"; then
    log_warn "Deploy of '$VERSION' FAILED, but rollback succeeded — system is back on the last known-good release."
    exit 1
else
    log_error "Deploy of '$VERSION' FAILED and rollback ALSO failed. System may be down. Manual intervention required."
    exit 2
fi
