#!/usr/bin/env bash
# Shared by every script in this pipeline. Sourced, not executed directly.

# DEPLOY_ROOT holds all RUNTIME state (releases, the `current` symlink,
# PID files) — deliberately separate from the repo's source tree, the way
# a real deploy target's state directory would be separate from the repo
# checked out onto a build server.
: "${DEPLOY_ROOT:=$(pwd)/.deploy-state}"
: "${APP_PORT:=8099}"
: "${HEALTH_CHECK_RETRIES:=10}"
: "${HEALTH_CHECK_DELAY:=0.5}"

log_info()  { printf '[%s] INFO  %s\n'  "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
log_warn()  { printf '[%s] WARN  %s\n'  "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
log_error() { printf '[%s] ERROR %s\n'  "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

releases_dir() { echo "$DEPLOY_ROOT/releases"; }
release_dir()  { echo "$(releases_dir)/$1"; }
current_link() { echo "$DEPLOY_ROOT/current"; }
last_good_file() { echo "$DEPLOY_ROOT/last_good_version.txt"; }

# Stops whatever process is recorded in a release dir's app.pid, if it's
# actually still running (PID files from a crashed process shouldn't cause
# this to error out — that's a real failure mode worth handling, not an
# edge case to ignore).
stop_release() {
    local dir="$1"
    local pid_file="$dir/app.pid"
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            # wait's exit status reflects the killed process's termination
            # (typically 143 for SIGTERM) — under `set -e` in the CALLING
            # script, letting that propagate would abort the whole deploy
            # right here, before a failed deploy ever reaches rollback.sh.
            # This bug was caught by actually running the rollback path,
            # not by inspection — `set -e` interacting with `wait` on a
            # killed process is exactly the kind of failure that looks
            # fine on paper and breaks the one time it matters.
            wait "$pid" 2>/dev/null || true
            log_info "Stopped process $pid ($dir)"
        fi
        rm -f "$pid_file"
    fi
}

# Starts a release's app.py in the background on the given port, writing
# its PID so stop_release() can find it later.
start_release() {
    local dir="$1"
    local port="$2"
    nohup python3 "$dir/app.py" "$port" > "$dir/app.log" 2>&1 &
    local pid=$!
    echo "$pid" > "$dir/app.pid"
    echo "$port" > "$dir/app.port"
    log_info "Started PID $pid on port $port ($dir)"
}
