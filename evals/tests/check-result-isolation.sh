#!/usr/bin/env bash
set -euo pipefail

EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$EVALS/run.sh"
REAL_MKTEMP="$(type -P mktemp)"
REAL_RM="$(type -P rm)"
TEST_ROOT="$($REAL_MKTEMP -d "${TMPDIR:-/tmp}/linked-records-result-isolation.XXXXXX")"
RESULT_DIRS=()
ESCAPED_TARGET="$EVALS/result-isolation-outside-$$"

cleanup() {
  local path

  for path in "${RESULT_DIRS[@]}"; do
    case "$path" in
    "$EVALS/results/"*) "$REAL_RM" -rf -- "$path" ;;
    *) echo "refusing to clean unexpected result path: $path" >&2 ;;
    esac
  done
  case "$TEST_ROOT" in
  "${TMPDIR:-/tmp}/linked-records-result-isolation."*)
    "$REAL_RM" -rf -- "$TEST_ROOT"
    ;;
  *) echo "refusing to clean unexpected test path: $TEST_ROOT" >&2 ;;
  esac
  case "$ESCAPED_TARGET" in
  "$EVALS/result-isolation-outside-"*) "$REAL_RM" -rf -- "$ESCAPED_TARGET" ;;
  *) echo "refusing to clean unexpected escape path: $ESCAPED_TARGET" >&2 ;;
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

register_summary() {
  local summary="$1"

  case "$summary" in
  "$EVALS/results/"*/summary.md)
    RESULT_DIRS+=("${summary%/summary.md}")
    ;;
  *) fail "runner reported an unexpected summary path: $summary" ;;
  esac
}

run_invalid_selection() {
  local name="$1"
  local scenario="$2"
  local label="${3:-}"
  local console="$TEST_ROOT/$name.console.txt"

  set +e
  if [ -n "$label" ]; then
    EVAL_LABEL="$label" bash "$RUNNER" claude "$scenario" >"$console" 2>&1
  else
    env -u EVAL_LABEL bash "$RUNNER" claude "$scenario" >"$console" 2>&1
  fi
  LAST_RC=$?
  set -e
  LAST_CONSOLE="$console"
  LAST_SUMMARY="$(sed -n 's/^summary: //p' "$console" | tail -n 1)"
  if [ -n "$LAST_SUMMARY" ]; then
    register_summary "$LAST_SUMMARY"
  fi
}

first_console="$TEST_ROOT/automatic-one.console.txt"
second_console="$TEST_ROOT/automatic-two.console.txt"
set +e
env -u EVAL_LABEL bash "$RUNNER" claude missing-one >"$first_console" 2>&1 &
first_pid=$!
env -u EVAL_LABEL bash "$RUNNER" claude missing-two >"$second_console" 2>&1 &
second_pid=$!
wait "$first_pid"
first_rc=$?
wait "$second_pid"
second_rc=$?
set -e
[ "$first_rc" -eq 2 ] || fail "first concurrent run returned $first_rc"
[ "$second_rc" -eq 2 ] || fail "second concurrent run returned $second_rc"
first_summary="$(sed -n 's/^summary: //p' "$first_console" | tail -n 1)"
second_summary="$(sed -n 's/^summary: //p' "$second_console" | tail -n 1)"
for automatic_summary in "$first_summary" "$second_summary"; do
  register_summary "$automatic_summary"
  [ -f "$automatic_summary" ] || fail "concurrent run did not create $automatic_summary"
done
[ "$first_summary" != "$second_summary" ] ||
  fail "concurrent automatic runs reused $first_summary"
assert_contains "$first_summary" 'missing-one'
assert_contains "$second_summary" 'missing-two'

escape_label="result-isolation-escape-$$"
escape_prefix="$EVALS/results/$(date +%Y-%m-%d)-claude-$escape_label"
mkdir -- "$escape_prefix"
RESULT_DIRS+=("$escape_prefix")
run_invalid_selection escaping-label missing-escape \
  "$escape_label/../../${ESCAPED_TARGET##*/}"
[ "$LAST_RC" -eq 2 ] || fail "escaping label returned $LAST_RC"
[ -z "$LAST_SUMMARY" ] || fail "escaping label reported a summary"
assert_contains "$LAST_CONSOLE" 'invalid EVAL_LABEL'
[ ! -e "$ESCAPED_TARGET" ] || fail "escaping label created $ESCAPED_TARGET"

label="result-isolation-$$"
run_invalid_selection labeled-one labeled-one "$label"
[ "$LAST_RC" -eq 2 ] || fail "first labeled run returned $LAST_RC"
[ -f "$LAST_SUMMARY" ] || fail "first labeled run did not create a summary"
labeled_summary="$LAST_SUMMARY"
saved_summary="$TEST_ROOT/labeled-summary.md"
cp "$labeled_summary" "$saved_summary"

run_invalid_selection labeled-two labeled-two "$label"
[ "$LAST_RC" -eq 2 ] || fail "colliding labeled run returned $LAST_RC"
[ -z "$LAST_SUMMARY" ] || fail "colliding labeled run reported a new summary"
assert_contains "$LAST_CONSOLE" 'result directory already exists'
cmp -s "$saved_summary" "$labeled_summary" ||
  fail "colliding labeled run changed existing evidence"

echo "PASS: eval result directories are isolated"
