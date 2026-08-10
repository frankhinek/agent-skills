#!/usr/bin/env bash
# Apply the common local-write boundary used by every eval harness.
set -uo pipefail

PROFILE_ID="eval-local-write-v1"
TEST_PROFILE_ID="eval-local-write-v1-test-backend"

resolve_backend() {
  if [ -n "${EVAL_SANDBOX_BIN:-}" ]; then
    echo "harness-sandbox.sh: EVAL_SANDBOX_BIN is unsupported; normal runs use Codex sandbox" >&2
    return 2
  fi

  if [ -n "${EVAL_TEST_SANDBOX_BIN:-}" ]; then
    [ "${EVAL_TESTING:-}" = 1 ] || {
      echo "harness-sandbox.sh: EVAL_TEST_SANDBOX_BIN requires EVAL_TESTING=1" >&2
      return 2
    }
    case "$EVAL_TEST_SANDBOX_BIN" in
    /*) ;;
    *) echo "harness-sandbox.sh: EVAL_TEST_SANDBOX_BIN must be absolute" >&2; return 2 ;;
    esac
    [ -x "$EVAL_TEST_SANDBOX_BIN" ] || {
      echo "harness-sandbox.sh: test sandbox backend is not executable" >&2
      return 127
    }
    printf '%s\n' "$EVAL_TEST_SANDBOX_BIN"
    return 0
  fi

  type -P codex 2>/dev/null || {
    echo "harness-sandbox.sh: codex sandbox backend not found" >&2
    return 127
  }
}

case "${1:-}" in
--profile-id)
  resolve_backend >/dev/null || exit $?
  if [ -n "${EVAL_TEST_SANDBOX_BIN:-}" ]; then
    echo "$TEST_PROFILE_ID"
  else
    echo "$PROFILE_ID"
  fi
  exit 0
  ;;
--backend-version)
  backend="$(resolve_backend)" || exit $?
  "$backend" --version
  exit $?
  ;;
esac

FIXTURE_INPUT="${1:?usage: harness-sandbox.sh <fixture> -- <command> [args ...]}"
shift
[ "${1:-}" = -- ] || {
  echo "harness-sandbox.sh: missing -- before command" >&2
  exit 2
}
shift
[ "$#" -gt 0 ] || {
  echo "harness-sandbox.sh: command is required" >&2
  exit 2
}
[ -d "$FIXTURE_INPUT" ] && [ ! -L "$FIXTURE_INPUT" ] || {
  echo "harness-sandbox.sh: fixture must be a real directory" >&2
  exit 2
}

FIXTURE="$(cd "$FIXTURE_INPUT" && pwd -P)" || exit 2
RUNTIME="$FIXTURE/.eval-runtime"
AGENTS="$FIXTURE/.agents"

case "$FIXTURE" in
*$'\n'*|*$'\r'*)
  echo "harness-sandbox.sh: fixture path contains a newline" >&2
  exit 2
  ;;
esac
[ -d "$RUNTIME/tmp" ] && [ ! -L "$RUNTIME" ] || {
  echo "harness-sandbox.sh: private runtime is missing or unsafe" >&2
  exit 2
}
[ -d "$AGENTS" ] && [ ! -L "$AGENTS" ] || {
  echo "harness-sandbox.sh: fixture .agents directory is missing or unsafe" >&2
  exit 2
}

backend="$(resolve_backend)" || exit $?
escaped_agents="${AGENTS//\\/\\\\}"
escaped_agents="${escaped_agents//\"/\\\"}"
writable_roots="[\"$escaped_agents\"]"

(
  cd "$FIXTURE" || exit 2
  TMPDIR="$RUNTIME/tmp" "$backend" sandbox \
    -c 'sandbox_mode="workspace-write"' \
    -c 'sandbox_workspace_write.exclude_tmpdir_env_var=true' \
    -c 'sandbox_workspace_write.exclude_slash_tmp=true' \
    -c "sandbox_workspace_write.writable_roots=$writable_roots" \
    -c 'sandbox_workspace_write.network_access=true' \
    -- "$@"
)
