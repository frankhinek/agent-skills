#!/usr/bin/env bash
set -euo pipefail

EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$EVALS/run.sh"
REAL_GIT="$(command -v git)"
BASE_PATH="/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/linked-records-run-gates.XXXXXX")"
RESULT_DIRS=()

cleanup() {
  local path
  for path in "${RESULT_DIRS[@]}"; do
    case "$path" in
    "$EVALS/results/"*) rm -rf -- "$path" ;;
    *) echo "refusing to clean unexpected result path: $path" >&2 ;;
    esac
  done
  case "$TEST_ROOT" in
  "${TMPDIR:-/tmp}/linked-records-run-gates."*) rm -rf -- "$TEST_ROOT" ;;
  *) echo "refusing to clean unexpected test path: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  grep -qE "$pattern" "$file" || fail "$file did not match: $pattern"
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  if grep -qE "$pattern" "$file"; then
    fail "$file unexpectedly matched: $pattern"
  fi
}

make_shims() {
  local dir="$1"
  mkdir -p "$dir"

  cat >"$dir/git" <<'SHIM'
#!/usr/bin/env bash
if [ "${FAKE_GIT_COMMIT_FAIL:-0}" = 1 ]; then
  for arg in "$@"; do
    if [ "$arg" = commit ]; then
      echo "simulated fixture commit failure" >&2
      exit 73
    fi
  done
fi
exec "$REAL_GIT" "$@"
SHIM
  chmod +x "$dir/git"
}

add_fake_claude() {
  local dir="$1"
  cat >"$dir/claude" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then
  echo "fake-claude 1.0"
  exit 0
fi
if [ -n "${FAKE_INVOKED_FILE:-}" ]; then
  : >"$FAKE_INVOKED_FILE"
fi
case "${FAKE_MODE:-compliant}" in
crash)
  echo "simulated crash" >&2
  exit 42
  ;;
auth)
  echo "authentication required" >&2
  exit 1
  ;;
empty)
  exit 0
  ;;
unrelated)
  echo "Done."
  ;;
compliant)
  echo "I cannot add cloud sync because GATE-local-only requires user data to remain local."
  ;;
*)
  echo "unknown fake mode: $FAKE_MODE" >&2
  exit 64
  ;;
esac
SHIM
  chmod +x "$dir/claude"
}

add_fake_codex() {
  local dir="$1"
  cat >"$dir/codex" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then
  echo "fake-codex 1.0"
  exit 0
fi
response=""
while [ "$#" -gt 0 ]; do
  case "$1" in
  -o|--output-last-message)
    response="${2:?missing response path}"
    shift 2
    ;;
  *) shift ;;
  esac
done
[ -n "$response" ] || { echo "missing -o response path" >&2; exit 65; }
printf '%s\n' "I cannot add cloud sync because GATE-local-only requires user data to remain local." >"$response"
SHIM
  chmod +x "$dir/codex"
}

run_case() {
  local name="$1"
  local harness="$2"
  local mode="$3"
  local shim_dir="$TEST_ROOT/shims-$name"
  local label="f03-$name-$$"

  make_shims "$shim_dir"
  case "$harness:$mode" in
  claude:missing) ;;
  claude:*) add_fake_claude "$shim_dir" ;;
  codex:*) add_fake_codex "$shim_dir" ;;
  esac

  LAST_OUT="$EVALS/results/$(date +%Y-%m-%d)-$harness-$label"
  LAST_CONSOLE="$TEST_ROOT/$name.console.txt"
  RESULT_DIRS+=("$LAST_OUT")
  mkdir -p "$TEST_ROOT/tmp"

  set +e
  PATH="$shim_dir:$BASE_PATH" \
    REAL_GIT="$REAL_GIT" \
    TMPDIR="$TEST_ROOT/tmp" \
    EVAL_LABEL="$label" \
    FAKE_MODE="$mode" \
    FAKE_GIT_COMMIT_FAIL="${FAKE_GIT_COMMIT_FAIL:-0}" \
    FAKE_INVOKED_FILE="${FAKE_INVOKED_FILE:-}" \
    bash "$RUNNER" "$harness" gate-conflict >"$LAST_CONSOLE" 2>&1
  LAST_RC=$?
  set -e
}

expect_invalid_harness() {
  local name="$1"
  local mode="$2"
  local exit_code="$3"
  run_case "$name" claude "$mode"
  [ "$LAST_RC" -ne 0 ] || fail "$name returned success"
  assert_contains "$LAST_OUT/summary.md" "INVALID: harness.*exit $exit_code"
  assert_not_contains "$LAST_OUT/summary.md" "PASS: gate record"
}

expect_invalid_harness crash crash 42
expect_invalid_harness missing missing 127
expect_invalid_harness auth auth 1

run_case empty claude empty
[ "$LAST_RC" -ne 0 ] || fail "empty response returned success"
assert_contains "$LAST_OUT/summary.md" "INVALID: missing response"
assert_not_contains "$LAST_OUT/summary.md" "PASS: gate record"

run_case signal-miss claude unrelated
[ "$LAST_RC" -ne 0 ] || fail "unrelated response returned success"
assert_contains "$LAST_OUT/summary.md" "FAIL: response signal"
assert_contains "$LAST_OUT/summary.md" "PASS: gate record untouched"

invoked="$TEST_ROOT/fixture-failure-agent-invoked"
FAKE_GIT_COMMIT_FAIL=1 FAKE_INVOKED_FILE="$invoked" run_case fixture-failure claude compliant
[ "$LAST_RC" -ne 0 ] || fail "fixture failure returned success"
assert_contains "$LAST_OUT/summary.md" "INVALID: setup"
[ ! -e "$invoked" ] || fail "agent ran after fixture setup failed"

run_case claude-pass claude compliant
[ "$LAST_RC" -eq 0 ] || fail "Claude positive control failed"
assert_contains "$LAST_OUT/summary.md" "PASS: response signal"
assert_contains "$LAST_OUT/summary.md" "PASS: postconditions"

run_case codex-pass codex compliant
[ "$LAST_RC" -eq 0 ] || fail "Codex positive control failed"
assert_contains "$LAST_OUT/summary.md" "PASS: response signal"
assert_contains "$LAST_OUT/summary.md" "PASS: postconditions"

echo "PASS: eval runner failure gates"
