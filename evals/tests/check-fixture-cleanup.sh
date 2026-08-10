#!/usr/bin/env bash
set -euo pipefail

EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$EVALS/run.sh"
REAL_MKTEMP="$(type -P mktemp)"
REAL_RM="$(type -P rm)"
BASE_PATH="/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin"
TEST_ROOT="$($REAL_MKTEMP -d "${TMPDIR:-/tmp}/linked-records-fixture-cleanup.XXXXXX")"
SANDBOX_BACKEND="$TEST_ROOT/sandbox-backend"
SHIM_DIR="$TEST_ROOT/shims"
RUN_DATE="$(date +%Y-%m-%d)"
RESULT_DIRS=()

unset BASH_ENV ENV
unset -f claude mktemp rm 2>/dev/null || true

cleanup() {
  local path
  for path in "${RESULT_DIRS[@]}"; do
    case "$path" in
    "$EVALS/results/"*) "$REAL_RM" -rf -- "$path" ;;
    *) echo "refusing to clean unexpected result path: $path" >&2 ;;
    esac
  done
  case "$TEST_ROOT" in
  "${TMPDIR:-/tmp}/linked-records-fixture-cleanup."*) "$REAL_RM" -rf -- "$TEST_ROOT" ;;
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

cat >"$SANDBOX_BACKEND" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then
  echo "fake-sandbox 1.0"
  exit 0
fi
[ "${1:-}" = sandbox ] || exit 90
shift
while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
  shift
done
[ "${1:-}" = -- ] || exit 91
shift
if [ "${1:-}" = /bin/sh ] && [ "${2:-}" = -c ] && [ "${4:-}" = sh ]; then
  printf '%s\n' contained >"${8:?missing inside-probe path}"
  exit 0
fi
exec "$@"
SHIM
chmod +x "$SANDBOX_BACKEND"

make_shims() {
  local dir="$1"
  mkdir -p "$dir"

  cat >"$dir/mktemp" <<'SHIM'
#!/usr/bin/env bash
runner_call=0
case "$*" in
*linked-records-eval.XXXXXX*) runner_call=1 ;;
esac
if [ "$runner_call" -eq 1 ]; then
  case "${FAKE_MKTEMP_MODE:-real}" in
  blank)
    exit 0
    ;;
  foreign)
    printf '%s\n' "$FAKE_FOREIGN_PATH"
    exit 0
    ;;
  esac
fi
path="$($REAL_MKTEMP "$@")" || exit $?
if [ "$runner_call" -eq 1 ]; then
  printf '%s\n' "$path" >>"$FAKE_MKTEMP_LOG"
fi
printf '%s\n' "$path"
SHIM

  cat >"$dir/rm" <<'SHIM'
#!/usr/bin/env bash
if [ "${FAKE_RM_MODE:-real}" = fail-root ] && [ -s "$FAKE_MKTEMP_LOG" ]; then
  target="$(sed -n '1p' "$FAKE_MKTEMP_LOG")"
  for arg in "$@"; do
    if [ "$arg" = "$target" ]; then
      echo "simulated eval fixture cleanup failure" >&2
      exit 91
    fi
  done
fi
exec "$REAL_RM" "$@"
SHIM

  cat >"$dir/claude" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then
  echo "fake-claude 1.0"
  exit 0
fi
: >"$FAKE_AGENT_MARKER"
case "${FAKE_AGENT_MODE:-pass}" in
pass)
  echo "I cannot add cloud sync because GATE-local-only requires local data. Linked-records activation is inert."
  ;;
crash)
  echo "simulated crash" >&2
  exit 42
  ;;
block-term|block-int)
  echo "partial response before interruption"
  printf '%s\n' "$$" >"$FAKE_CHILD_PID_FILE"
  exec sleep 30
  ;;
*) exit 93 ;;
esac
SHIM

  chmod +x "$dir/mktemp" "$dir/rm" "$dir/claude"
}

run_case() {
  local name="$1"
  local agent_mode="$2"
  local retention="$3"
  local mktemp_mode="${4:-real}"
  local rm_mode="${5:-real}"
  local scenarios
  local label
  local runner_command
  local case_env
  local signal

  if [ "$#" -ge 5 ]; then
    shift 5
  else
    shift "$#"
  fi
  scenarios=("$@")
  label="fixture-cleanup-$name-$$"

  if [ "${#scenarios[@]}" -eq 0 ]; then
    scenarios=(gate-conflict)
  fi
  runner_command=(/bin/bash "$RUNNER" claude "${scenarios[@]}")

  LAST_CONSOLE="$TEST_ROOT/$name.console.txt"
  LAST_MKTEMP_LOG="$TEST_ROOT/$name.mktemp.txt"
  LAST_AGENT_MARKER="$TEST_ROOT/$name.agent-invoked"
  LAST_CHILD_PID_FILE="$TEST_ROOT/$name.child-pid.txt"
  LAST_OUT="$EVALS/results/$RUN_DATE-claude-$label"
  RESULT_DIRS+=("$LAST_OUT")
  : >"$LAST_MKTEMP_LOG"
  case_env=(
    "PATH=$SHIM_DIR:$BASE_PATH"
    "REAL_MKTEMP=$REAL_MKTEMP"
    "REAL_RM=$REAL_RM"
    "TMPDIR=$TEST_ROOT/tmp"
    "EVAL_LABEL=$label"
    "EVAL_TESTING=1"
    "EVAL_TEST_SANDBOX_BIN=$SANDBOX_BACKEND"
    "EVAL_FIXTURE_RETENTION=$retention"
    "FAKE_AGENT_MODE=$agent_mode"
    "FAKE_AGENT_MARKER=$LAST_AGENT_MARKER"
    "FAKE_CHILD_PID_FILE=$LAST_CHILD_PID_FILE"
    "FAKE_MKTEMP_LOG=$LAST_MKTEMP_LOG"
    "FAKE_MKTEMP_MODE=$mktemp_mode"
    "FAKE_FOREIGN_PATH=${FAKE_FOREIGN_PATH:-}"
    "FAKE_RM_MODE=$rm_mode"
  )

  case "$agent_mode" in
  block-term|block-int)
    case "$agent_mode" in
    block-term) signal=TERM ;;
    block-int) signal=INT ;;
    esac
    runner_command=(/bin/sh -c '
      runner=$1
      marker=$2
      signal=$3
      shift 3
      (
        while [ ! -s "$marker" ]; do sleep 0.05; done
        kill -"$signal" "$$"
      ) &
      exec /bin/bash "$runner" claude "$@"
    ' sh "$RUNNER" "$LAST_CHILD_PID_FILE" "$signal" "${scenarios[@]}")
    ;;
  esac

  set +e
  env "${case_env[@]}" "${runner_command[@]}" >"$LAST_CONSOLE" 2>&1
  LAST_RC=$?
  set -e
}

captured_root() {
  [ -s "$LAST_MKTEMP_LOG" ] || fail "runner scratch path was not captured"
  sed -n '1p' "$LAST_MKTEMP_LOG"
}

assert_child_stopped() {
  local pid

  [ -s "$LAST_CHILD_PID_FILE" ] || fail "fake agent PID was not captured"
  pid="$(sed -n '1p' "$LAST_CHILD_PID_FILE")"
  if kill -0 "$pid" 2>/dev/null; then
    fail "interrupted run left fake agent $pid running"
  fi
}

mkdir -p "$TEST_ROOT/tmp"
make_shims "$SHIM_DIR"

run_case success pass never
success_root="$(captured_root)"
[ "$LAST_RC" -eq 0 ] || fail "successful run returned $LAST_RC"
[ ! -e "$success_root" ] || fail "successful run retained $success_root"
[ -s "$LAST_OUT/summary.md" ] || fail "successful cleanup removed the summary"
[ -s "$LAST_OUT/logs/gate-conflict.response.txt" ] ||
  fail "successful cleanup removed the final response"
for remaining_root in "$TEST_ROOT/tmp"/linked-records-eval.*; do
  [ -e "$remaining_root" ] || continue
  fail "successful run left an untracked root at $remaining_root"
done

run_case multi-scenario pass always real real gate-conflict bare-activation
multi_root="$(captured_root)"
[ "$LAST_RC" -eq 0 ] || fail "multi-scenario run returned $LAST_RC"
[ "$(awk 'END { print NR }' "$LAST_MKTEMP_LOG")" -eq 1 ] ||
  fail "multi-scenario run created more than one runner scratch root"
[ -d "$multi_root/1-gate-conflict/fixture" ] ||
  fail "first scenario was not created below the shared root"
[ -d "$multi_root/2-bare-activation/fixture" ] ||
  fail "second scenario was not created below the shared root"
assert_contains "$LAST_CONSOLE" "retained eval fixtures: $multi_root"

run_case failure crash never
failure_root="$(captured_root)"
[ "$LAST_RC" -ne 0 ] || fail "crashing harness returned success"
[ ! -e "$failure_root" ] || fail "failed run retained $failure_root"
[ -s "$LAST_OUT/summary.md" ] || fail "failure cleanup removed the summary"

run_case retain-failure crash failed
retained_failure_root="$(captured_root)"
[ "$LAST_RC" -ne 0 ] || fail "retained failed run returned success"
[ -d "$retained_failure_root" ] || fail "failed retention removed its fixture root"
assert_contains "$LAST_CONSOLE" "retained eval fixtures: $retained_failure_root"

run_case cleanup-success-in-failed-mode pass failed
failed_mode_success_root="$(captured_root)"
[ "$LAST_RC" -eq 0 ] || fail "successful failed-mode run returned $LAST_RC"
[ ! -e "$failed_mode_success_root" ] ||
  fail "failed retention kept a successful run"

run_case retain-success pass always
retained_success_root="$(captured_root)"
[ "$LAST_RC" -eq 0 ] || fail "retained successful run returned $LAST_RC"
[ -d "$retained_success_root" ] || fail "debug retention removed its fixture root"
assert_contains "$LAST_CONSOLE" "retained eval fixtures: $retained_success_root"

term_sibling="$TEST_ROOT/tmp/term-sibling"
printf '%s\n' untouched >"$term_sibling"
term_started=$SECONDS
run_case term block-term never
term_root="$(captured_root)"
[ "$LAST_RC" -eq 143 ] || fail "TERM returned $LAST_RC instead of 143"
[ "$((SECONDS - term_started))" -lt 15 ] || fail "TERM did not stop promptly"
[ ! -e "$term_root" ] || fail "TERM retained $term_root"
assert_child_stopped
[ -s "$LAST_OUT/logs/gate-conflict.response.txt" ] ||
  fail "TERM lost the partial final response"
assert_contains "$LAST_OUT/summary.md" "INVALID: interrupted \(exit 143\)"
[ "$(sed -n '1p' "$term_sibling")" = untouched ] ||
  fail "TERM cleanup changed an unrelated sibling"

int_sibling="$TEST_ROOT/tmp/int-sibling"
printf '%s\n' untouched >"$int_sibling"
int_started=$SECONDS
run_case int block-int never
int_root="$(captured_root)"
[ "$LAST_RC" -eq 130 ] || fail "INT returned $LAST_RC instead of 130"
[ "$((SECONDS - int_started))" -lt 15 ] || fail "INT did not stop promptly"
[ ! -e "$int_root" ] || fail "INT retained $int_root"
assert_child_stopped
[ -s "$LAST_OUT/logs/gate-conflict.response.txt" ] ||
  fail "INT lost the partial final response"
assert_contains "$LAST_OUT/summary.md" "INVALID: interrupted \(exit 130\)"
[ "$(sed -n '1p' "$int_sibling")" = untouched ] ||
  fail "INT cleanup changed an unrelated sibling"

foreign="$TEST_ROOT/foreign"
mkdir -p "$foreign"
printf '%s\n' untouched >"$foreign/sentinel.txt"
FAKE_FOREIGN_PATH="$foreign" run_case unsafe pass never foreign
[ "$LAST_RC" -ne 0 ] || fail "unsafe temporary root returned success"
[ ! -e "$LAST_AGENT_MARKER" ] || fail "agent ran with an unsafe temporary root"
[ "$(sed -n '1p' "$foreign/sentinel.txt")" = untouched ] ||
  fail "unsafe temporary-root handling changed a foreign path"

run_case blank pass never blank
[ "$LAST_RC" -ne 0 ] || fail "blank temporary root returned success"
[ ! -e "$LAST_AGENT_MARKER" ] || fail "agent ran with a blank temporary root"

run_case invalid-retention pass sometimes
[ "$LAST_RC" -eq 2 ] || fail "invalid retention returned $LAST_RC instead of 2"
[ ! -s "$LAST_MKTEMP_LOG" ] || fail "invalid retention created a temporary root"
[ ! -e "$LAST_AGENT_MARKER" ] || fail "agent ran with invalid retention"

run_case cleanup-failure pass never real fail-root
cleanup_failure_root="$(captured_root)"
[ "$LAST_RC" -ne 0 ] || fail "cleanup failure returned success"
[ -d "$cleanup_failure_root" ] || fail "cleanup failure lost diagnostic evidence"
assert_contains "$LAST_CONSOLE" "cleanup failed.*$cleanup_failure_root"

echo "PASS: eval fixture cleanup"
