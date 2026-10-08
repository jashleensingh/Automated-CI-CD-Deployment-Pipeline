# Automated CI/CD Deployment Pipeline

Bash scripts that provision an environment, deploy a release, health-check
it, and automatically roll back to the last known-good release if that
health check fails — wired into a GitHub Actions workflow that builds a
Docker image and runs this exact deploy/rollback cycle on every push to
`main`. Zero external dependencies (pure bash + Python stdlib for the demo
app), so every number below is real, reproducible output from actually
running it — not a description of what it's supposed to do.

## A real bug this project actually caught

Worth leading with, because it's the most honest evidence this was really
tested rather than just written: the first version of `stop_release()` in
`common.sh` did `kill "$pid"; wait "$pid"`. Under `set -euo pipefail`,
`wait`'s exit status reflects the killed process's termination (typically
143, for SIGTERM) — a non-zero status that `set -e` treats as a script
failure. The result: the very first time a broken deploy tried to roll
back, `deploy.sh` died at the `stop_release` call *inside the rollback
path itself*, before `rollback.sh` ever ran. The symlink still pointed at
the old release, which looked right at a glance — but the old release's
process had already been killed and never restarted, so the service was
actually down with no live process behind it.

This was only caught by actually running the failure path end-to-end and
checking for a real process with `ps`, not by reading the code or trusting
the exit code. Fix: `wait "$pid" 2>/dev/null || true` — rollback doesn't
care about the killed process's historical exit status, only that it's
stopped. See the comment in `common.sh` for the full explanation.

## Verified — real output from this repo's own runs

`scripts/demo.sh` runs the whole story in one command: provision, a real
successful deploy, a **deliberately broken** deploy that has to actually
trigger and complete a real rollback (not a mocked one), then a 50-cycle
test suite. Real output from running it:

```
--- Deploy v1.0.0 (healthy) ---
Health check passed on attempt 2/10 (port 8099)
Deploy of 'v1.0.0' succeeded and is now live.
{"status": "ok", "version": "v1.0.0"}

--- Deploy v1.1.0 (deliberately broken) ---
Deliberately deploying a broken release (test mode) to exercise the rollback path.
Health check failed after 10 attempts (port 8099)
Deploy of 'v1.1.0' failed its health check. Stopping it and rolling back.
Rolling back to last known-good release: v1.0.0
Rollback successful — v1.0.0 is live again.
deploy.sh exit code: 1 (failed deploy, but rollback succeeded)
{"status": "ok", "version": "v1.0.0"}        <- still actually serving
2345 python3 .../releases/v1.0.0/app.py 8099  <- a REAL running process, confirmed via ps
```

### The 50-cycle test suite — real numbers behind the resume bullet

```
============================================
 Test Suite Results
============================================
Total cycles:                  50
  - New version accepted:      43
  - Rollback triggered + OK:   7
  - Catastrophic (DOWN):       0
Completion rate (ended healthy): 100.0%
Elapsed time:                  64s
============================================
```

Ran this twice independently (once inside `demo.sh`, once standalone) and
got the same result both times: 50/50 cycles, including 7 deliberately
broken releases (roughly 1 in 7, by design — see `run_test_suite.sh`),
left the system in a healthy, responding state every single time. 100%
in this run — the resume line says 99%+ deliberately, since 50 runs is
real evidence of robustness, not a formal guarantee that failure modes
outside what this suite exercises (disk full, network partition mid-
rollback, etc.) can never occur.

**On "45 minutes to under 5 minutes":** that comparison needs a real
manual-deployment baseline to mean anything, which isn't something this
sandbox can fabricate honestly. What IS real: the automated cycle above —
provision, deploy, health-check, and (when needed) roll back — completes
in about 1 second per cycle in normal operation. Swap in whatever your
own actual manual-deploy timing was for the resume's specific numbers.

### Shellcheck — genuinely clean, not just "no errors shown"

```
$ shellcheck -x scripts/*.sh
(no output — zero warnings, zero info-level notices, on any script)
```

## Architecture

```
.github/workflows/deploy.yml
  lint              shellcheck every script
  build-image        docker build + push to GHCR (uses the repo's own
                       built-in GITHUB_TOKEN — no external secrets needed)
  deploy-and-verify    provision -> deploy -> curl /health -> deliberately
                         broken deploy (proves rollback) -> full test suite

scripts/
  common.sh    shared logging + start_release/stop_release helpers
  provision.sh  idempotent environment setup (dirs, required-tool checks)
  deploy.sh      stop old -> start new -> health-check -> promote OR
                  auto-rollback on failure
  health_check.sh  retry-based polling (a fresh process needs a moment
                     to bind its port — one failed check isn't fatal)
  rollback.sh       reverts to the last release that passed its health
                      check; same code path whether triggered
                      automatically by deploy.sh or run by hand
  run_test_suite.sh  runs N deploy cycles (mix of good + deliberately
                       broken), reports a REAL completion rate
  demo.sh             the whole story in one command
```

**Deployment model**: a `releases/<version>/` directory per release plus
a `current` symlink that atomically repoints to whichever release is
live (the same pattern tools like Capistrano popularized) — not `docker
run`/`docker stop` directly. This was a deliberate choice: it's fully
testable without a Docker daemon (this sandbox doesn't have one), and the
mechanics — stop old, start new, health-check, promote-or-rollback — are
identical regardless of whether "start" means launching a process or
starting a container. The Dockerfile and the GHCR push in the workflow are
real and would work in an actual GitHub Actions run; swapping `deploy.sh`'s
`start_release`/`stop_release` calls for `docker run`/`docker stop` against
the pushed image is a contained change, not a redesign.

## Running it

```bash
bash scripts/demo.sh
```

That's the whole thing. To explore the pieces individually:

```bash
export DEPLOY_ROOT="$(pwd)/.deploy-state"   # optional, this is the default
bash scripts/provision.sh
bash scripts/deploy.sh v1.0.0 app
curl http://127.0.0.1:8099/health

bash scripts/deploy.sh v1.1.0 app --inject-broken   # watch it auto-rollback
bash scripts/run_test_suite.sh 50                     # or any N
```

Lint the scripts yourself:
```bash
shellcheck -x scripts/*.sh
```

## What actually ran here vs. what's design-only

Genuinely executed in this sandbox: every bash script, the demo end-to-
end, the 50-cycle test suite (twice), shellcheck on all scripts, and
PyYAML validation of the workflow file's syntax.

**Not run here, and this matters**: the actual GitHub Actions workflow
itself — there's no real Actions runner available in this sandbox, so
`deploy.yml` has been syntax-validated (valid YAML) and carefully reviewed
but never executed by GitHub's own infrastructure. Push it and watch the
first real run before trusting it blindly, the same way you should treat
any pipeline you didn't personally watch go green.

## Possible extensions

- Blue/green on two ports instead of stop-then-start on one, for actual
  zero-downtime deploys (this version has a brief gap between stopping
  the old release and the new one passing its health check).
- Real remote deploy via SSH (the workflow currently deploys to the
  runner itself as a self-contained demo).
- Structured JSON logs instead of plain text, for easier parsing by a
  monitoring system.
