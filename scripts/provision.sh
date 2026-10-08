#!/usr/bin/env bash
# Provisions the deployment target's directory structure and checks that
# required tools are present. Idempotent on purpose — a provisioning step
# that fails or corrupts state when run a second time against an
# already-provisioned target is a real, common source of pipeline
# flakiness, so this is safe to call on every single pipeline run rather
# than only "the first time."
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

log_info "Provisioning deploy target at $DEPLOY_ROOT"

for cmd in python3 curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command '$cmd' not found on this host."
        exit 1
    fi
done

mkdir -p "$(releases_dir)"

if [[ ! -e "$(last_good_file)" ]]; then
    : > "$(last_good_file)"  # empty file — "no known-good release yet" is a valid, expected state
fi

log_info "Provisioning complete."
