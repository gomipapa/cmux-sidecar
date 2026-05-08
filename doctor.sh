#!/usr/bin/env bash
# cmux-sidecar doctor — checks dependencies and exits 0 if all green, 1 otherwise.
# Output only. Never installs, never starts services.
set -uo pipefail

CODE_SERVER_URL="${CMUX_SIDECAR_URL:-${CMUX_CODE_VIEWER_URL:-http://127.0.0.1:8080}}"

fail=0

check() {
  local label="$1" cmd="$2" version_flag="${3:---version}"
  local resolved
  resolved="$(command -v "$cmd" 2>/dev/null || true)"
  if [[ -z "$resolved" ]]; then
    printf '✗ %-15s : not found in PATH\n' "$label"
    fail=1
    return
  fi
  local ver
  ver="$("$cmd" $version_flag 2>&1 | head -n 1 || true)"
  printf '✓ %-15s : %s\n' "$label" "${ver:-$resolved}"
}

check "code-server"   code-server   --version
check "cmux"          cmux          --version
check "curl"          curl          --version
check "python3"       python3       --version

# cmux-sidecar binary
sidecar="$(command -v cmux-sidecar 2>/dev/null || true)"
if [[ -n "$sidecar" ]]; then
  printf '✓ %-15s : %s\n' "cmux-sidecar" "$sidecar"
else
  printf '✗ %-15s : not found in PATH (run install.sh)\n' "cmux-sidecar"
  fail=1
fi

# code-server liveness
if curl -sSf -o /dev/null "$CODE_SERVER_URL/healthz" 2>/dev/null; then
  printf '✓ %-15s : %s/healthz responded\n' "code-server up" "$CODE_SERVER_URL"
else
  printf '✗ %-15s : %s/healthz no response (will lazy-start on first use)\n' "code-server up" "$CODE_SERVER_URL"
  # not a hard failure — wrapper starts it lazily. Don't bump $fail.
fi

exit "$fail"
