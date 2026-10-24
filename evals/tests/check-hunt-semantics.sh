#!/usr/bin/env bash
set -euo pipefail
EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/assurance-hunt-check.XXXXXX")"
cleanup() {
  case "$TEST_ROOT" in
  "${TMPDIR:-/tmp}/assurance-hunt-check."*) rm -rf -- "$TEST_ROOT" ;;
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
for scenario in hunt-recovery hunt-retry hunt-clean hunt-uncertain hunt-authority hunt-routine; do
  FIXTURE="$TEST_ROOT/$scenario"
  "$EVALS/fixture.sh" "$FIXTURE" >"$TEST_ROOT/fixture.log"
  cp -R "$EVALS/scenarios/$scenario/overlay/." "$FIXTURE/"
  git -C "$FIXTURE" add -A
  git -C "$FIXTURE" commit -qm overlay
  BASE="$(git -C "$FIXTURE" rev-parse HEAD)"
  expect_checker 1
  python3 "$EVALS/tests/hunt-controls.py" "$scenario" "$FIXTURE"
  expect_checker 0
  if [ "$scenario" = hunt-routine ]; then
    printf 'Unrequested hunt\n' >"$FIXTURE/hunt-report.md"
    expect_checker 1
    rm "$FIXTURE/hunt-report.md"
  else
    cp "$FIXTURE/hunt-report.md" "$TEST_ROOT/report.md"
    : >"$FIXTURE/hunt-report.md"
    expect_checker 1
    rm "$FIXTURE/hunt-report.md"
    ln -s "$TEST_ROOT/report.md" "$FIXTURE/hunt-report.md"
    expect_checker 1
    rm "$FIXTURE/hunt-report.md"
    cp "$TEST_ROOT/report.md" "$FIXTURE/hunt-report.md"
  fi
  case "$scenario" in
  hunt-uncertain)
    mkdir -p "$FIXTURE/tests"
    ln -s absent.py "$FIXTURE/tests/hunt_witness.py"
    expect_checker 1
    rm "$FIXTURE/tests/hunt_witness.py"
    ;;
  hunt-recovery|hunt-retry)
    cp "$FIXTURE/tests/hunt_witness.py" "$TEST_ROOT/witness.py"
    for code in 0 1; do
      printf 'raise SystemExit(%s)\n' "$code" >"$FIXTURE/tests/hunt_witness.py"
      expect_checker 1
    done
    cp "$TEST_ROOT/witness.py" "$FIXTURE/tests/hunt_witness.py"
    ;;
  esac
  printf '\nUnauthorized change.\n' >>"$FIXTURE/specs/CLAIM-single-writer.md"
  expect_checker 1
  git -C "$FIXTURE" add specs/CLAIM-single-writer.md
  expect_checker 1
  git -C "$FIXTURE" commit -qm 'simulate unauthorized claim edit'
  expect_checker 1
  git -C "$FIXTURE" show "$BASE:specs/CLAIM-single-writer.md" >"$FIXTURE/specs/CLAIM-single-writer.md"
  expect_checker 0
  printf '\n# Unauthorized repair\n' >>"$FIXTURE/app/store.py"
  expect_checker 1
  git -C "$FIXTURE" show "$BASE:app/store.py" >"$FIXTURE/app/store.py"
  printf '\nChanged authority.\n' >>"$FIXTURE/.agents/skills/assurance-records/SKILL.md"
  expect_checker 1
done
echo 'PASS: hunt witness controls and protected artifact boundaries'
