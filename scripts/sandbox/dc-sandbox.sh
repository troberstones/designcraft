#!/usr/bin/env bash
# Build and run DesignCraft inside a macOS sandbox (sandbox-exec, profile: dc.sb next to this
# script): no network except loopback, no reads of common secret directories, writes only in the
# repo, ~/.cargo and temp dirs. Dependency build scripts and the app run under it.
#
#   dc-sandbox.sh build            fetch deps (network; downloads only, nothing is built or run),
#                                  then build offline inside the sandbox
#   dc-sandbox.sh run [args...]    run the GUI app (sample document, throwaway settings dir)
#   dc-sandbox.sh control [port]   like run, with the control port (default 7979) and a random
#                                  DESIGNCRAFT_CONTROL_TOKEN, printed at startup
#   dc-sandbox.sh cli [args...]    run designcraft-cli, e.g. cli run --sample --export out.png
#
# sandbox-exec is deprecated by Apple but still works. The profile is a deny list; see dc.sb.
set -euo pipefail

[[ "$(uname)" == Darwin ]] || { echo "dc-sandbox.sh needs macOS (sandbox-exec)" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PROFILE="$HERE/dc.sb"
[[ -f "$REPO/Cargo.lock" && -f "$PROFILE" ]] || { echo "run this from a DesignCraft checkout" >&2; exit 1; }
export PATH="${RUSTUP_HOME_BIN:-/opt/homebrew/opt/rustup/bin}:$HOME/.cargo/bin:$PATH"
cd "$REPO"

sandboxed() { sandbox-exec -D "HOME=$HOME" -D "REPO=$REPO" -f "$PROFILE" "$@"; }

# Fresh settings/recovery directory per run, removed on exit.
PDIR=""
trap '[[ -z "$PDIR" ]] || rm -rf "$PDIR"' EXIT INT TERM
profile_dir() { PDIR="$(mktemp -d "${TMPDIR:-/tmp}/dc-profile.XXXXXX")"; }

need_build() {
  [[ -x target/release/designcraft && -x target/release/designcraft-cli ]] || { echo "not built yet: run '$0 build' first" >&2; exit 1; }
}

rc=0
cmd="${1:-}"
(( $# )) && shift
case "$cmd" in
  build)
    echo "==> fetching dependencies (network; downloads only)"
    cargo fetch --locked
    echo "==> building offline inside the sandbox"
    sandboxed cargo build --release --locked --offline -p designcraft -p designcraft-cli
    ;;
  run)
    need_build; profile_dir
    DESIGNCRAFT_CONFIG_DIR="$PDIR" sandboxed target/release/designcraft --sample "$@" || rc=$?
    ;;
  control)
    need_build; profile_dir
    port="${1:-7979}"
    (( $# )) && shift
    token="$(uuidgen)"
    echo "control port 127.0.0.1:$port"
    echo "token: $token   (send as a top-level \"token\" field; MCP: export DESIGNCRAFT_CONTROL_TOKEN=$token)"
    DESIGNCRAFT_CONFIG_DIR="$PDIR" DESIGNCRAFT_CONTROL_TOKEN="$token" sandboxed target/release/designcraft --sample --control "$port" "$@" || rc=$?
    ;;
  cli)
    need_build; profile_dir
    DESIGNCRAFT_CONFIG_DIR="$PDIR" sandboxed target/release/designcraft-cli "$@" || rc=$?
    ;;
  *)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    [[ -z "$cmd" ]] || exit 2
    ;;
esac
exit "$rc"
