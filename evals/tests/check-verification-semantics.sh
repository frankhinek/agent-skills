#!/usr/bin/env bash
set -euo pipefail
EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/assurance-verification-check.XXXXXX")"
cleanup() {
  case "$TEST_ROOT" in
  "${TMPDIR:-/tmp}/assurance-verification-check."*) rm -rf -- "$TEST_ROOT" ;;
  *) echo "refusing to clean unexpected root: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_checker() {
  local expected="$1" rc=0
  (cd "$FIXTURE" && EVAL_BASE="$BASE" bash "$EVALS/scenarios/$scenario/check.sh") \
    >"$TEST_ROOT/check.log" 2>&1 || rc=$?
  if [ "$rc" -ne "$expected" ]; then
    cat "$TEST_ROOT/check.log" >&2
    fail "$scenario expected $expected, got $rc"
  fi
}
expect_witness() {
  local script="$1" expected="$2" rc=0
  (cd "$FIXTURE" && python3 "$script") >"$TEST_ROOT/witness.log" 2>&1 || rc=$?
  [ "$rc" -eq "$expected" ] || fail "$scenario witness expected $expected, got $rc"
}
for scenario in verify-fresh verify-valid verify-unavailable composition-gap \
  witness-partial witness-repaired witness-unavailable; do
  FIXTURE="$TEST_ROOT/$scenario"
  "$EVALS/fixture.sh" "$FIXTURE" >"$TEST_ROOT/fixture.log"
  cp -R "$EVALS/scenarios/$scenario/overlay/." "$FIXTURE/"
  git -C "$FIXTURE" add -A
  git -C "$FIXTURE" commit -qm overlay
  BASE="$(git -C "$FIXTURE" rev-parse HEAD)"
  expect_checker 1
  case "$scenario" in
  composition-gap) witness=tests/witness_retry.py; before=1; after=1; claim=cache-once ;;
  witness-unavailable) witness=tests/replay_ttl.py; before=1; after=1; claim=cache-ttl ;;
  verify-fresh|witness-partial) witness=tests/witness_ttl.py; before=1; after=1; claim=cache-ttl ;;
  witness-repaired) witness=tests/witness_ttl.py; before=1; after=0; claim=cache-ttl ;;
  *) witness=tests/witness_ttl.py; before=0; after=0; claim=cache-ttl ;;
  esac
  expect_witness "$witness" "$before"
  if [ "$scenario" = witness-unavailable ]; then
    grep -q ModuleNotFoundError "$TEST_ROOT/witness.log" || fail 'missing-driver control did not fail as expected'
  fi
  python3 "$EVALS/tests/verification-controls.py" "$scenario" "$FIXTURE"
  expect_witness "$witness" "$after"
  expect_checker 0
  cp "$FIXTURE/$witness" "$TEST_ROOT/witness.py"
  printf '\n# weakened witness\n' >>"$FIXTURE/$witness"
  expect_checker 1
  cp "$TEST_ROOT/witness.py" "$FIXTURE/$witness"
  evidence="$FIXTURE/specs/CLAIM-$claim/verification.md"
  cp "$evidence" "$TEST_ROOT/evidence.md"
  correct="$(tail -1 "$evidence")"
  for verdict in pass provisional falsified; do
    [ "$correct" != "Result: $verdict" ] || continue
    printf '\nResult: %s\n' "$verdict" >>"$evidence"
    expect_checker 1
    cp "$TEST_ROOT/evidence.md" "$evidence"
  done
  printf '\nChanged claim scope.\n' >>"$FIXTURE/specs/CLAIM-$claim.md"
  expect_checker 1
  git -C "$FIXTURE" add "specs/CLAIM-$claim.md"
  expect_checker 1
  git -C "$FIXTURE" commit -qm 'simulate unauthorized claim edit'
  expect_checker 1
  git -C "$FIXTURE" show "$BASE:specs/CLAIM-$claim.md" >"$FIXTURE/specs/CLAIM-$claim.md"
  expect_checker 0
  printf '\nChanged authority.\n' >>"$FIXTURE/.agents/skills/assurance-records-claims/SKILL.md"
  expect_checker 1
done
echo 'PASS: witness execution, repair behavior, verdicts, and protected artifact controls'
