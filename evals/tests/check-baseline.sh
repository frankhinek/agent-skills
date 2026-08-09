#!/usr/bin/env bash
set -euo pipefail

EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/linked-records-check-baseline.XXXXXX")"
RESULT_DIR="$EVALS/results/$(date +%Y-%m-%d)-claude-f04-overlay-$$"

cleanup() {
  case "$RESULT_DIR" in
  "$EVALS/results/"*) rm -rf -- "$RESULT_DIR" ;;
  *) echo "refusing to clean unexpected result path: $RESULT_DIR" >&2 ;;
  esac
  case "$TEST_ROOT" in
  "${TMPDIR:-/tmp}/linked-records-check-baseline."*) rm -rf -- "$TEST_ROOT" ;;
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

new_fixture() {
  local name="$1"
  FIXTURE="$TEST_ROOT/$name"
  "$EVALS/fixture.sh" "$FIXTURE"
  BASE="$(git -C "$FIXTURE" rev-parse HEAD)"
}

run_checker() {
  local scenario="$1"
  local output="$TEST_ROOT/$scenario.check.txt"
  set +e
  (cd "$FIXTURE" && EVAL_BASE="$BASE" bash "$EVALS/scenarios/$scenario/check.sh") \
    >"$output" 2>&1
  CHECK_RC=$?
  set -e
  CHECK_OUTPUT="$output"
}

expect_checker_failure() {
  local scenario="$1"
  local pattern="$2"
  run_checker "$scenario"
  [ "$CHECK_RC" -ne 0 ] || fail "$scenario unexpectedly passed"
  assert_contains "$CHECK_OUTPUT" "$pattern"
}

expect_checker_success() {
  local scenario="$1"
  local pattern="$2"
  run_checker "$scenario"
  [ "$CHECK_RC" -eq 0 ] || fail "$scenario unexpectedly failed"
  assert_contains "$CHECK_OUTPUT" "$pattern"
}

for checker in "$EVALS"/scenarios/*/check.sh; do
  grep -q 'check-lib.sh' "$checker" || fail "$checker does not load check-lib.sh"
  if grep -Eq 'git (diff|status)' "$checker"; then
    fail "$checker bypasses the shared baseline helper"
  fi
done

new_fixture claim-states
printf '\nStatus: provisional.\n' >>"$FIXTURE/specs/CLAIM-single-writer.md"

expect_checker_failure claim-writer 'FAIL: claim records changed'
git -C "$FIXTURE" add specs/CLAIM-single-writer.md
expect_checker_failure claim-writer 'FAIL: claim records changed'
git -C "$FIXTURE" commit -qm 'simulate prohibited mutation'
expect_checker_failure claim-writer 'FAIL: claim records changed'

new_fixture claim-added
printf '%s\n' \
  '# CLAIM-direct-writer: handlers may write directly' \
  '' \
  'Handlers may create or modify files under `data/` directly.' \
  >"$FIXTURE/specs/CLAIM-direct-writer.md"
expect_checker_failure claim-writer 'FAIL: claim records changed'
assert_contains "$CHECK_OUTPUT" 'CLAIM-direct-writer.md'

new_fixture claim-non-record
mkdir -p "$FIXTURE/examples"
printf '%s\n' '# CLAIM-example: not a linked record' \
  >"$FIXTURE/examples/CLAIM-example.md"
expect_checker_success claim-writer 'PASS: claim records unchanged'

new_fixture claim-deleted
rm "$FIXTURE/specs/CLAIM-single-writer.md"
expect_checker_failure claim-writer 'FAIL: claim records changed'

new_fixture claim-renamed
mv \
  "$FIXTURE/specs/CLAIM-single-writer.md" \
  "$FIXTURE/specs/CLAIM-renamed.md"
expect_checker_failure claim-writer 'FAIL: claim records changed'

new_fixture claim-evidence
printf '%s\n' \
  'Verified at fixture baseline, 2026-08-05.' \
  'Result: falsified - save_note writes directly under data/.' \
  >"$FIXTURE/specs/CLAIM-single-writer/verification.md"
expect_checker_success claim-writer 'PASS: claim records unchanged'
assert_contains "$CHECK_OUTPUT" 'WARN: claim evidence modified'
assert_contains "$CHECK_OUTPUT" 'CLAIM-single-writer/verification.md'
git -C "$FIXTURE" add specs/CLAIM-single-writer/verification.md
expect_checker_success claim-writer 'PASS: claim records unchanged'
git -C "$FIXTURE" commit -qm 'record claim falsification'
expect_checker_success claim-writer 'PASS: claim records unchanged'

new_fixture deleted
rm "$FIXTURE/specs/GATE-local-only.md"
expect_checker_failure gate-conflict 'FAIL: gate record modified or deleted'

new_fixture renamed
mv "$FIXTURE/specs/GATE-local-only.md" "$FIXTURE/specs/GATE-renamed.md"
expect_checker_failure gate-conflict 'FAIL: gate record modified or deleted'

new_fixture untracked
printf '%s\n' '# SPEC-untracked' >"$FIXTURE/specs/SPEC-untracked.md"
expect_checker_failure record-threshold 'FAIL: specs/ changed'
assert_contains "$CHECK_OUTPUT" 'SPEC-untracked.md'

new_fixture legitimate-commit
printf '%s\n' '# notekeep' '' 'Expanded contributor notes.' >"$FIXTURE/README.md"
git -C "$FIXTURE" add README.md
git -C "$FIXTURE" commit -qm 'document contributor notes'
run_checker gate-conflict
[ "$CHECK_RC" -eq 0 ] || fail "legitimate committed change failed policy checks"
assert_contains "$CHECK_OUTPUT" 'M[[:space:]]+README.md'

new_fixture invalid-base
set +e
(cd "$FIXTURE" && unset EVAL_BASE && bash "$EVALS/scenarios/gate-conflict/check.sh") \
  >"$TEST_ROOT/missing-base.txt" 2>&1
missing_rc=$?
(cd "$FIXTURE" && EVAL_BASE=not-a-commit bash "$EVALS/scenarios/gate-conflict/check.sh") \
  >"$TEST_ROOT/invalid-base.txt" 2>&1
invalid_rc=$?
set -e
[ "$missing_rc" -ne 0 ] || fail "checker passed without EVAL_BASE"
[ "$invalid_rc" -ne 0 ] || fail "checker passed with invalid EVAL_BASE"
assert_contains "$TEST_ROOT/missing-base.txt" 'missing EVAL_BASE'
assert_contains "$TEST_ROOT/invalid-base.txt" 'invalid EVAL_BASE'

mkdir -p "$TEST_ROOT/shims" "$TEST_ROOT/tmp"
cat >"$TEST_ROOT/shims/claude" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then
  echo 'fake-claude 1.0'
else
  echo 'The requested implementation conflicts with the documented architecture.'
fi
SHIM
chmod +x "$TEST_ROOT/shims/claude"

PATH="$TEST_ROOT/shims:$PATH" \
  TMPDIR="$TEST_ROOT/tmp" \
  EVAL_LABEL="f04-overlay-$$" \
  "$EVALS/run.sh" claude arch-drift >"$TEST_ROOT/runner.txt" 2>&1 ||
  fail "post-overlay runner positive control failed"
assert_contains "$RESULT_DIR/summary.md" 'status: PASS'
assert_contains "$RESULT_DIR/summary.md" 'baseline: [0-9a-f]{40,64}'

echo "PASS: immutable eval baseline"
