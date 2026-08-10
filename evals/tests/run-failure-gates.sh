#!/usr/bin/env bash
set -euo pipefail

EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$EVALS/run.sh"
REAL_GIT="$(command -v git)"
REAL_MKTEMP="$(command -v mktemp)"
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

add_fake_mktemp() {
  local dir="$1"
  cat >"$dir/mktemp" <<'SHIM'
#!/usr/bin/env bash
if [ -n "${FAKE_MKTEMP_INVOKED_FILE:-}" ]; then
  : >"$FAKE_MKTEMP_INVOKED_FILE"
fi
exec "$REAL_MKTEMP" "$@"
SHIM
  chmod +x "$dir/mktemp"
}

add_fake_claude() {
  local dir="$1"
  cat >"$dir/claude" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then
  if [ -n "${FAKE_VERSION_INVOKED_FILE:-}" ]; then
    : >"$FAKE_VERSION_INVOKED_FILE"
  fi
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
  case "$*" in
  *'.groom-sample'*)
      printf '%s\n' \
        'specs/ARCH-app.md' \
        'specs/ARCH-groom-alpha.md' \
        'specs/ARCH-groom-beta.md' \
        'specs/GATE-local-only.md' \
        'specs/REQ-groom-alpha.md' \
        'specs/REQ-groom-beta.md' \
        'specs/REQ-groom-gamma.md' \
        'specs/SPEC-groom-alpha.md' \
        'specs/SPEC-groom-beta.md' \
        'specs/SPEC-groom-gamma.md' \
        >.groom-sample
    echo "I groomed the precommitted sample while protecting claims and evidence."
    ;;
  *'sorting object keys'*)
    python3 - <<'PY'
from pathlib import Path

path = Path("app/store.py")
path.write_text(path.read_text().replace(
    "json.dump(value, f)",
    "json.dump(value, f, sort_keys=True)",
))
PY
    cat >>specs/CLAIM-single-writer/verification.md <<'EOF'

The app/store.py implementation changed after the previous pass.
Current result: provisional.
The prior pass no longer covers Store.write in the updated source.
Before restoring a pass, regenerate the writer enumeration.
EOF
    echo "I implemented deterministic writes. CLAIM-single-writer is unchanged; its evidence is provisional pending re-verification."
    ;;
  *'briefly explain when it should be used'*)
    echo "The linked-records skill governs qualified ARCH, REQ, SPEC, GATE, and CLAIM records; bare activation is inert."
    ;;
  *)
    echo "I cannot add cloud sync because GATE-local-only requires user data to remain local."
    ;;
  esac
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
  local runner_args=("$harness")
  shift 3
  [ "$#" -eq 0 ] || runner_args+=("$@")

  make_shims "$shim_dir"
  [ -z "${FAKE_MKTEMP_INVOKED_FILE:-}" ] || add_fake_mktemp "$shim_dir"
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
    REAL_MKTEMP="$REAL_MKTEMP" \
    TMPDIR="$TEST_ROOT/tmp" \
    EVAL_LABEL="$label" \
    FAKE_MODE="$mode" \
    FAKE_GIT_COMMIT_FAIL="${FAKE_GIT_COMMIT_FAIL:-0}" \
    FAKE_INVOKED_FILE="${FAKE_INVOKED_FILE:-}" \
    FAKE_MKTEMP_INVOKED_FILE="${FAKE_MKTEMP_INVOKED_FILE:-}" \
    FAKE_VERSION_INVOKED_FILE="${FAKE_VERSION_INVOKED_FILE:-}" \
    bash "$RUNNER" "${runner_args[@]}" >"$LAST_CONSOLE" 2>&1
  LAST_RC=$?
  set -e
}

expect_selection_error() {
  local name="$1"
  shift
  local agent_marker="$TEST_ROOT/$name-agent-invoked"
  local fixture_marker="$TEST_ROOT/$name-fixture-invoked"
  local version_marker="$TEST_ROOT/$name-version-invoked"

  FAKE_INVOKED_FILE="$agent_marker" \
    FAKE_MKTEMP_INVOKED_FILE="$fixture_marker" \
    FAKE_VERSION_INVOKED_FILE="$version_marker" \
    run_case "$name" claude compliant "$@"
  [ "$LAST_RC" -eq 2 ] || fail "$name returned $LAST_RC instead of usage exit 2"
  assert_contains "$LAST_OUT/summary.md" 'INVALID: scenario selection'
  assert_contains "$LAST_OUT/summary.md" 'scenarios executed: 0'
  [ ! -e "$version_marker" ] || fail "$name queried the harness version"
  [ ! -e "$fixture_marker" ] || fail "$name created a fixture"
  [ ! -e "$agent_marker" ] || fail "$name invoked the agent"
}

expect_invalid_harness() {
  local name="$1"
  local mode="$2"
  local exit_code="$3"
  run_case "$name" claude "$mode" gate-conflict
  [ "$LAST_RC" -ne 0 ] || fail "$name returned success"
  assert_contains "$LAST_OUT/summary.md" "INVALID: harness.*exit $exit_code"
  assert_not_contains "$LAST_OUT/summary.md" "PASS: gate record"
}

expect_invalid_harness crash crash 42
expect_invalid_harness missing missing 127
expect_invalid_harness auth auth 1

run_case empty claude empty gate-conflict
[ "$LAST_RC" -ne 0 ] || fail "empty response returned success"
assert_contains "$LAST_OUT/summary.md" "INVALID: missing response"
assert_not_contains "$LAST_OUT/summary.md" "PASS: gate record"

run_case signal-miss claude unrelated gate-conflict
[ "$LAST_RC" -ne 0 ] || fail "unrelated response returned success"
assert_contains "$LAST_OUT/summary.md" "FAIL: response signal"
assert_contains "$LAST_OUT/summary.md" "PASS: gate record untouched"

invoked="$TEST_ROOT/fixture-failure-agent-invoked"
FAKE_GIT_COMMIT_FAIL=1 FAKE_INVOKED_FILE="$invoked" run_case fixture-failure claude compliant gate-conflict
[ "$LAST_RC" -ne 0 ] || fail "fixture failure returned success"
assert_contains "$LAST_OUT/summary.md" "INVALID: setup"
[ ! -e "$invoked" ] || fail "agent ran after fixture setup failed"

version_marker="$TEST_ROOT/claude-pass-version-invoked"
fixture_marker="$TEST_ROOT/claude-pass-fixture-invoked"
FAKE_VERSION_INVOKED_FILE="$version_marker" \
  FAKE_MKTEMP_INVOKED_FILE="$fixture_marker" \
  run_case claude-pass claude compliant gate-conflict
[ "$LAST_RC" -eq 0 ] || fail "Claude positive control failed"
assert_contains "$LAST_OUT/summary.md" "PASS: response signal"
assert_contains "$LAST_OUT/summary.md" "PASS: postconditions"
[ -e "$version_marker" ] || fail "version marker never fired; selection checks could be vacuous"
[ -e "$fixture_marker" ] || fail "fixture marker never fired; selection checks could be vacuous"

run_case codex-pass codex compliant gate-conflict
[ "$LAST_RC" -eq 0 ] || fail "Codex positive control failed"
assert_contains "$LAST_OUT/summary.md" "PASS: response signal"
assert_contains "$LAST_OUT/summary.md" "PASS: postconditions"

run_case groom-pass claude compliant groom-claims
[ "$LAST_RC" -eq 0 ] || fail "groom-claims positive control failed"
assert_contains "$LAST_OUT/summary.md" "PASS: response signal"
assert_contains "$LAST_OUT/summary.md" "PASS: postconditions"
assert_contains "$LAST_OUT/summary.md" \
  'PASS: captured grooming sample contains only eligible records'

run_case activation-pass claude compliant bare-activation
[ "$LAST_RC" -eq 0 ] || fail "bare-activation positive control failed"
assert_contains "$LAST_OUT/summary.md" "PASS: response signal"
assert_contains "$LAST_OUT/summary.md" "PASS: postconditions"
assert_contains "$LAST_OUT/summary.md" \
  'PASS: bare activation left all records and claim evidence unchanged'

run_case staleness-pass claude compliant claim-staleness
[ "$LAST_RC" -eq 0 ] || fail "claim-staleness positive control failed"
assert_contains "$LAST_OUT/summary.md" "PASS: response signal"
assert_contains "$LAST_OUT/summary.md" "PASS: postconditions"
assert_contains "$LAST_OUT/summary.md" \
  'PASS: claim verification is provisional with a specific re-verification need'

expect_selection_error unknown-only does-not-exist
assert_contains "$LAST_OUT/summary.md" 'does-not-exist'

expect_selection_error mixed-selection gate-conflict missing-one missing-two
assert_contains "$LAST_OUT/summary.md" 'missing-one'
assert_contains "$LAST_OUT/summary.md" 'missing-two'
assert_not_contains "$LAST_OUT/summary.md" '^## gate-conflict$'

expect_selection_error empty-name ''
assert_contains "$LAST_OUT/summary.md" '<empty>'

expect_selection_error path-alias ./gate-conflict
assert_contains "$LAST_OUT/summary.md" '\./gate-conflict'

empty_evals="$TEST_ROOT/empty-evals"
empty_shims="$TEST_ROOT/shims-empty-discovery"
empty_label="f17-empty-discovery-$$"
empty_out="$empty_evals/results/$(date +%Y-%m-%d)-claude-$empty_label"
empty_console="$TEST_ROOT/empty-discovery.console.txt"
empty_agent_marker="$TEST_ROOT/empty-discovery-agent-invoked"
empty_fixture_marker="$TEST_ROOT/empty-discovery-fixture-invoked"
empty_version_marker="$TEST_ROOT/empty-discovery-version-invoked"
mkdir -p "$empty_evals/scenarios"
cp "$RUNNER" "$empty_evals/run.sh"
make_shims "$empty_shims"
add_fake_mktemp "$empty_shims"
add_fake_claude "$empty_shims"
set +e
PATH="$empty_shims:$BASE_PATH" \
  REAL_GIT="$REAL_GIT" \
  REAL_MKTEMP="$REAL_MKTEMP" \
  TMPDIR="$TEST_ROOT/tmp" \
  EVAL_LABEL="$empty_label" \
  FAKE_MODE=compliant \
  FAKE_INVOKED_FILE="$empty_agent_marker" \
  FAKE_MKTEMP_INVOKED_FILE="$empty_fixture_marker" \
  FAKE_VERSION_INVOKED_FILE="$empty_version_marker" \
  bash "$empty_evals/run.sh" claude >"$empty_console" 2>&1
empty_rc=$?
set -e
[ "$empty_rc" -eq 2 ] || fail "empty discovery returned $empty_rc instead of usage exit 2"
assert_contains "$empty_out/summary.md" 'INVALID: scenario selection'
assert_contains "$empty_out/summary.md" 'scenarios executed: 0'
[ ! -e "$empty_version_marker" ] || fail "empty discovery queried the harness version"
[ ! -e "$empty_fixture_marker" ] || fail "empty discovery created a fixture"
[ ! -e "$empty_agent_marker" ] || fail "empty discovery invoked the agent"

run_case default-all claude compliant
assert_not_contains "$LAST_OUT/summary.md" 'INVALID:'
for scenario in arch-drift bare-activation claim-staleness claim-writer gate-conflict gate-sweep-edit groom-claims record-threshold; do
  assert_contains "$LAST_OUT/summary.md" "^## $scenario$"
done

echo "PASS: eval runner failure gates"
