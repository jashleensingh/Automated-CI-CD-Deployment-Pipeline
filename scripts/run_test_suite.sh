#!/usr/bin/env bash
# Usage: run_test_suite.sh [num_cycles]
#
# Runs num_cycles deploy attempts, deliberately injecting a broken release
# roughly 1 in 7 times (prime-ish spacing so it doesn't line up with any
# round-number pattern in num_cycles), and measures "completion rate" as:
# after each cycle, is the service actually responding to /health with a
# 200? That's deliberately NOT the same as "did the new version ship" — a
# cycle where a bad release gets caught and rolled back is a SUCCESSFUL
# outcome for a deployment pipeline, not a failure. A pipeline that can
# only report success when nothing ever goes wrong isn't measuring the
# thing that actually matters in production.
set -uo pipefail  # NOT -e here: this script's whole job is to keep going through expected per-cycle failures and tally results
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

NUM_CYCLES="${1:-50}"
APP_SOURCE_DIR="$SCRIPT_DIR/../app"

TOTAL=0
HEALTHY_END_STATE=0
NEW_VERSION_ACCEPTED=0
ROLLBACK_TRIGGERED_AND_SUCCEEDED=0
CATASTROPHIC=0

log_info "Starting test suite: $NUM_CYCLES deploy cycles"
bash "$SCRIPT_DIR/provision.sh" >/dev/null

START_TIME=$(date +%s)

for ((i = 1; i <= NUM_CYCLES; i++)); do
    TOTAL=$((TOTAL + 1))
    VERSION="test-$i"

    if ((i % 7 == 0)); then
        INJECT="--inject-broken"
    else
        INJECT=""
    fi

    # shellcheck disable=SC2086  # intentionally unquoted: empty when not injecting, a single flag token when it is
    bash "$SCRIPT_DIR/deploy.sh" "$VERSION" "$APP_SOURCE_DIR" $INJECT >/tmp/cycle-$i.log 2>&1
    DEPLOY_EXIT=$?

    if curl -sf --max-time 2 -o /dev/null "http://127.0.0.1:${APP_PORT}/health"; then
        HEALTHY_END_STATE=$((HEALTHY_END_STATE + 1))
        if [[ "$DEPLOY_EXIT" -eq 0 ]]; then
            NEW_VERSION_ACCEPTED=$((NEW_VERSION_ACCEPTED + 1))
        else
            ROLLBACK_TRIGGERED_AND_SUCCEEDED=$((ROLLBACK_TRIGGERED_AND_SUCCEEDED + 1))
        fi
    else
        CATASTROPHIC=$((CATASTROPHIC + 1))
        log_error "Cycle $i ($VERSION): system NOT healthy after deploy.sh exited $DEPLOY_EXIT — see /tmp/cycle-$i.log"
    fi
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

COMPLETION_RATE=$(awk "BEGIN { printf \"%.1f\", ($HEALTHY_END_STATE / $TOTAL) * 100 }")

echo
echo "============================================"
echo " Test Suite Results"
echo "============================================"
echo "Total cycles:                  $TOTAL"
echo "  - New version accepted:      $NEW_VERSION_ACCEPTED"
echo "  - Rollback triggered + OK:   $ROLLBACK_TRIGGERED_AND_SUCCEEDED"
echo "  - Catastrophic (DOWN):       $CATASTROPHIC"
echo "Completion rate (ended healthy): ${COMPLETION_RATE}%"
echo "Elapsed time:                  ${ELAPSED}s"
echo "============================================"

if [[ "$CATASTROPHIC" -gt 0 ]]; then
    exit 1
fi
exit 0
