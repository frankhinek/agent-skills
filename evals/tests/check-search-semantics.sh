#!/usr/bin/env bash
set -euo pipefail

EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/linked-records-search-semantics.XXXXXX")"

cleanup() {
  case "$TEST_ROOT" in
  "${TMPDIR:-/tmp}/linked-records-search-semantics."*) rm -rf -- "$TEST_ROOT" ;;
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
  local scenario="$1"
  local name="$2"
  FIXTURE="$TEST_ROOT/$name"
  "$EVALS/fixture.sh" "$FIXTURE"
  cp -R "$EVALS/scenarios/$scenario/overlay/." "$FIXTURE/"
  git -C "$FIXTURE" add -A
  git -C "$FIXTURE" commit -qm overlay
  BASE="$(git -C "$FIXTURE" rev-parse HEAD)"
}

run_checker() {
  local scenario="$1"
  CHECK_OUTPUT="$TEST_ROOT/$scenario.check.txt"
  set +e
  (cd "$FIXTURE" && EVAL_BASE="$BASE" bash "$EVALS/scenarios/$scenario/check.sh") \
    >"$CHECK_OUTPUT" 2>&1
  CHECK_RC=$?
  set -e
}

expect_success() {
  local scenario="$1"
  local pattern="$2"
  run_checker "$scenario"
  [ "$CHECK_RC" -eq 0 ] || fail "$scenario unexpectedly failed"
  assert_contains "$CHECK_OUTPUT" "$pattern"
}

expect_failure() {
  local scenario="$1"
  local pattern="$2"
  run_checker "$scenario"
  [ "$CHECK_RC" -ne 0 ] || fail "$scenario unexpectedly passed"
  assert_contains "$CHECK_OUTPUT" "$pattern"
}

write_complete_search_proof() {
  mkdir -p "$FIXTURE/specs/CLAIM-clamped-score"
  cat >"$FIXTURE/specs/CLAIM-clamped-score/proof.md" <<'EOF'
## Scope
app/score.py, tests/search_clamp.py, and tests/search-config.json.
## Model and quantifiers
Sampled generated search; budget 2000 over -10000..10000.
## Axioms
Python seeded random behavior.
## Argument
1. `search` — seed 1729 reproduces the run. The branch-based oracle checks
   clamp_score imported from production app/score.py. The named negative
   control unclamped_mutant is rejected with a counterexample.
## Residuals
Unexplored inputs remain.
## Weakest links
The search finds counterexamples only inside its sampled budget.
EOF
}

write_provisional_staleness() {
  cat >>"$FIXTURE/specs/CLAIM-clamped-score/verification.md" <<'EOF'

tests/search-config.json now expands the generated search domain beyond the
recorded run.
Result: provisional
Rerun the named negative control and search at the current revision before pass.
EOF
}

expand_search_config() {
  python3 - "$FIXTURE/tests/search-config.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as handle:
    config = json.load(handle)
config["max_abs"] = 20000
with open(path, "w") as handle:
    json.dump(config, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

update_search_proof_for_staleness() {
  cat >>"$FIXTURE/specs/CLAIM-clamped-score/proof.md" <<'EOF'

The current configuration extends to 20,000, while the recorded run covered
only 10,000. The search lemma is stale until the unclamped_mutant negative
control and search are rerun for the wider domain.
EOF
}

write_provisional_nonvacuity() {
  cat >"$FIXTURE/specs/CLAIM-policy-decision/verification.md" <<'EOF'
The oracle is self-derived from the implementation output's logged intent, and
the proof records no rejected negative control or mutation.
Result: provisional
The evidence cannot establish the policy property independently.
EOF
}

new_fixture search-proof proof-complete
write_complete_search_proof
expect_success search-proof 'PASS: claim proof was created as a regular file'
assert_contains "$CHECK_OUTPUT" 'PASS: proof-only request did not create verification evidence'

new_fixture search-proof proof-mislabeled
mkdir -p "$FIXTURE/specs/CLAIM-clamped-score"
printf '%s\n' '1. `test` — generated cases passed.' \
  >"$FIXTURE/specs/CLAIM-clamped-score/proof.md"
expect_failure search-proof 'FAIL: search lemma must record'

new_fixture search-staleness staleness-complete
expand_search_config
write_provisional_staleness
expect_success search-staleness 'PASS: requested search-domain configuration change is exact'
assert_contains "$CHECK_OUTPUT" 'PASS: changed search configuration demoted the verdict with exact restoration work'

new_fixture search-staleness staleness-updated-proof
expand_search_config
update_search_proof_for_staleness
write_provisional_staleness
expect_success search-staleness 'PASS: changed proof distinguishes the recorded run from stale current coverage'

new_fixture search-staleness staleness-invalid-proof
expand_search_config
printf '%s\n' 'Current search configuration changed.' \
  >>"$FIXTURE/specs/CLAIM-clamped-score/proof.md"
write_provisional_staleness
expect_failure search-staleness 'FAIL: proof was removed or changed without preserving the recorded run and stale coverage'

new_fixture search-staleness staleness-no-evidence
expand_search_config
expect_failure search-staleness 'FAIL: stale search verification was not updated'

new_fixture search-nonvacuity nonvacuity-complete
write_provisional_nonvacuity
expect_success search-nonvacuity 'PASS: vacuous search evidence supports only a provisional verdict'

new_fixture search-nonvacuity nonvacuity-false-pass
cat >"$FIXTURE/specs/CLAIM-policy-decision/verification.md" <<'EOF'
The generated search returned green.
Result: pass
EOF
expect_failure search-nonvacuity 'FAIL: self-derived oracle or missing rejected negative control'

new_fixture search-nonvacuity nonvacuity-false-falsified
cat >"$FIXTURE/specs/CLAIM-policy-decision/verification.md" <<'EOF'
The proof is structurally inadequate but supplies no claim counterexample.
Result: falsified
EOF
expect_failure search-nonvacuity 'FAIL: self-derived oracle or missing rejected negative control'

echo "PASS: search-rung semantic eval checks"
