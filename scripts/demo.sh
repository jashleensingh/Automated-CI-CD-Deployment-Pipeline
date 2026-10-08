#!/usr/bin/env bash
# One command, the whole story: provision -> a real successful deploy ->
# a deliberately broken deploy that proves auto-rollback actually works
# (not just that the code exists) -> the full repeated-cycle test suite.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"
APP_SOURCE_DIR="$SCRIPT_DIR/../app"

rm -rf "$DEPLOY_ROOT"

echo "############################################"
echo "# 1. Provision"
echo "############################################"
bash "$SCRIPT_DIR/provision.sh"

echo
echo "############################################"
echo "# 2. Deploy v1.0.0 (a normal, healthy release)"
echo "############################################"
bash "$SCRIPT_DIR/deploy.sh" v1.0.0 "$APP_SOURCE_DIR"
echo "--- confirming it's actually live ---"
curl -s "http://127.0.0.1:${APP_PORT}/health"; echo

echo
echo "############################################"
echo "# 3. Deploy v1.1.0 — DELIBERATELY BROKEN"
echo "#    (this is what actually proves rollback works,"
echo "#     not just that the code for it exists)"
echo "############################################"
bash "$SCRIPT_DIR/deploy.sh" v1.1.0 "$APP_SOURCE_DIR" --inject-broken
echo "deploy.sh exit code: $? (1 = failed deploy, but rollback succeeded)"
echo "--- confirming the service is STILL up, on the old version ---"
curl -s "http://127.0.0.1:${APP_PORT}/health"; echo
echo "--- confirming a real process is running ---"
pgrep -fa "app.py" || true

echo
echo "############################################"
echo "# 4. Full test suite: 50 cycles, ~1-in-7 deliberately broken"
echo "############################################"
bash "$SCRIPT_DIR/run_test_suite.sh" 50

echo
echo "Demo complete."
