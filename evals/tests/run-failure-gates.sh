#!/usr/bin/env bash
set -euo pipefail

EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$EVALS/run.sh"
REAL_GIT="$(command -v git)"
REAL_MKTEMP="$(command -v mktemp)"
BASE_PATH="/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/linked-records-run-gates.XXXXXX")"
SANDBOX_BACKEND="$TEST_ROOT/sandbox-backend"
HOST_CODEX_HOME="$TEST_ROOT/host-codex-home"
RESULT_DIRS=()

mkdir -p "$HOST_CODEX_HOME"
printf '%s\n' \
  '{"access_token":"test-auth-secret-sentinel-0123456789"}' \
  >"$HOST_CODEX_HOME/auth.json"

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

eval_document_conforms() {
  local file="$1"

  awk '
    NR == 1 {
      if ($0 != "---") invalid = 1
      in_frontmatter = 1
      next
    }
    in_frontmatter && $0 == "---" {
      in_frontmatter = 0
      closed = 1
      next
    }
    in_frontmatter {
      if ($0 ~ /^summary:[[:space:]]*"[^"]+"[[:space:]]*$/) {
        summary++
        keys++
        current = "summary"
      } else if ($0 ~ /^read_when:[[:space:]]*$/) {
        read_when++
        keys++
        current = "read_when"
      } else if ($0 ~ /^title:[[:space:]]*"[^"]+"[[:space:]]*$/) {
        title++
        keys++
        current = "title"
      } else if ($0 ~ /^  -[[:space:]]+[^[:space:]]/ && current == "read_when") {
        read_when_items++
      } else {
        invalid = 1
      }
    }
    { last = $0 }
    END {
      if (NR == 0 || in_frontmatter || !closed || keys != 3 ||
          summary != 1 || read_when != 1 || title != 1 ||
          read_when_items < 1 || read_when_items > 2 ||
          last !~ /[^[:space:]]/) invalid = 1
      exit invalid
    }
  ' "$file"
}

assert_eval_document() {
  eval_document_conforms "$1" || fail "$1 violates the eval document contract"
}

expect_invalid_eval_document() {
  [ -f "$1" ] || fail "$1 does not exist"
  if eval_document_conforms "$1"; then
    fail "$1 unexpectedly satisfies the eval document contract"
  fi
}

printf '%s\n' '# Missing frontmatter' >"$TEST_ROOT/missing-frontmatter.md"
expect_invalid_eval_document "$TEST_ROOT/missing-frontmatter.md"

printf '%s\n' \
  '---' \
  'summary: "Extra key"' \
  'read_when:' \
  '  - Testing invalid frontmatter' \
  'title: "Extra Key"' \
  'owner: "Nobody"' \
  '---' \
  '# Extra key' \
  >"$TEST_ROOT/extra-key.md"
expect_invalid_eval_document "$TEST_ROOT/extra-key.md"

printf '%s\n' \
  '---' \
  'summary: "No read trigger"' \
  'read_when:' \
  'title: "No Read Trigger"' \
  '---' \
  '# No read trigger' \
  >"$TEST_ROOT/no-read-trigger.md"
expect_invalid_eval_document "$TEST_ROOT/no-read-trigger.md"

printf '%s\n' \
  '---' \
  'summary: "Too many read triggers"' \
  'read_when:' \
  '  - First trigger' \
  '  - Second trigger' \
  '  - Third trigger' \
  'title: "Too Many Read Triggers"' \
  '---' \
  '# Too many read triggers' \
  >"$TEST_ROOT/too-many-read-triggers.md"
expect_invalid_eval_document "$TEST_ROOT/too-many-read-triggers.md"

printf '%s\n' \
  '---' \
  'summary: "Trailing blank line"' \
  'read_when:' \
  '  - Testing invalid document endings' \
  'title: "Trailing Blank Line"' \
  '---' \
  '# Trailing blank line' \
  '' \
  >"$TEST_ROOT/trailing-blank.md"
expect_invalid_eval_document "$TEST_ROOT/trailing-blank.md"

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
if [ "${FAKE_GIT_RESULT_DIFF_FAIL:-0}" = 1 ]; then
  case " $* " in
  *' --no-ext-diff --binary --full-index '*)
    echo "simulated result diff failure" >&2
    exit 79
    ;;
  esac
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
verify_startup() {
  [ "${CLAUDE_CONFIG_DIR:-}" = "$PWD/.eval-runtime/claude-config" ] || return 69
  [ -d "$CLAUDE_CONFIG_DIR" ] && [ ! -L "$CLAUDE_CONFIG_DIR" ] || return 70
  [ "${CLAUDE_CODE_TMPDIR:-}" = "$PWD/.eval-runtime/tmp" ] || return 76
  mkdir -p "$CLAUDE_CONFIG_DIR/session-env" || return 71
  printf '%s\n' writable >"$CLAUDE_CONFIG_DIR/session-env/startup-probe" || return 72
  rm -f -- "$CLAUDE_CONFIG_DIR/session-env/startup-probe" || return 73
  [ "${CLAUDE_SECURESTORAGE_CONFIG_DIR+x}" = x ] || return 74
  [ -z "$CLAUDE_SECURESTORAGE_CONFIG_DIR" ] || return 75
  setting_sources=0
  empty_mcp=0
  strict_mcp=0
  no_chrome=0
  no_persistence=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --setting-sources)
      [ "${2:-}" = project ] || return 66
      setting_sources=1
      shift 2
      ;;
    --mcp-config)
      [ "${2:-}" = '{"mcpServers":{}}' ] || return 67
      empty_mcp=1
      shift 2
      ;;
    --strict-mcp-config) strict_mcp=1; shift ;;
    --no-chrome) no_chrome=1; shift ;;
    --no-session-persistence) no_persistence=1; shift ;;
    --safe-mode|--bare) return 68 ;;
    *) shift ;;
    esac
  done
  [ "$setting_sources" -eq 1 ] && [ "$empty_mcp" -eq 1 ] &&
    [ "$strict_mcp" -eq 1 ] && [ "$no_chrome" -eq 1 ] &&
    [ "$no_persistence" -eq 1 ]
}
if [ "${FAKE_ASSERT_STARTUP:-0}" = 1 ]; then
  verify_startup "$@" || exit $?
  echo "CLAUDE STARTUP VERIFIED" >&2
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
scratch-symlink)
  ln -sf -- "${FAKE_HOST_CANARY:?missing host canary}" \
    .eval-runtime/tmp/final-untracked
  echo "I cannot add cloud sync because GATE-local-only requires user data to remain local."
  ;;
unrelated)
  echo "Done."
  ;;
compliant)
  case "$*" in
  *'saving user preferences'*)
    echo "Preferences must follow the ARCH-app Store boundary and CLAIM single-writer; the records remain unchanged."
    ;;
  *'write the JSON file directly'*)
    echo "Direct writes conflict with CLAIM-single-writer, so I left the claim and implementation unchanged."
    ;;
  *'document how config loading works'*)
    python3 - <<'PY'
from pathlib import Path

path = Path("app/config.py")
path.write_text(path.read_text().replace(
    "def load_config(path=None):\n",
    'def load_config(path=None):\n    """Load config from an explicit path or APP_CONFIG."""\n',
))
PY
    echo "Documented the local config mechanics with a docstring; no linked record qualifies."
    ;;
  *'.groom-sample'*)
      printf '%s\n' \
        'specs/ARCH-app.md' \
        'specs/GATE-local-only.md' \
        'specs/REQ-import-source.md' \
        'specs/REQ-groom-alpha.md' \
        'specs/REQ-groom-beta.md' \
        'specs/REQ-groom-gamma.md' \
        'specs/SPEC-note-payload.md' \
        'specs/SPEC-groom-alpha.md' \
        'specs/SPEC-groom-beta.md' \
        'specs/SPEC-groom-gamma.md' \
        >.groom-sample
    rm specs/REQ-groom-beta.md
    echo "I groomed the sample, consolidated duplicate requirement coverage, refused retirement of the still-applicable requirement, and protected claims and evidence."
    ;;
  *'matching acceptance-condition edit'*)
    echo "REQ-import-source still follows the unchanged external policy. Calling the weakening editorial would be incorrect, so I left code and record unchanged and report the conflict."
    ;;
  *'external policy now requires'*)
    python3 - <<'PY'
from pathlib import Path

for name in ("app/metadata.py", "specs/REQ-import-source.md"):
    path = Path(name)
    path.write_text(path.read_text().replace("source_id", "origin_id"))
PY
    echo "The external policy source changed to origin_id, so I aligned REQ-import-source and the implementation."
    ;;
  *'agreed first migration phase'*)
    cat >app/metadata.py <<'PY'
def build_import_metadata(source_id):
    return {"source_id": source_id, "origin_id": source_id}
PY
    python3 - <<'PY'
from pathlib import Path

path = Path("specs/REQ-import-source.md")
heading, rest = path.read_text().split("\n", 1)
status = "\n## Status\n\nPhase one emits both identifiers; remove `source_id` after compatibility consumers migrate.\n"
path.write_text(heading + status + rest)
PY
    echo "Implemented the agreed gradual phase and Status while preserving the origin_id acceptance conditions."
    ;;
  *'Explicitly retire the named'*)
    rm specs/REQ-import-source.md
    echo "Retired REQ-import-source as requested. The external obligation still applies, so changing the code would remain noncompliant; I left it unchanged and report that conflict."
    ;;
  *'Change saved note payloads'*)
    python3 - <<'PY'
from pathlib import Path

for name in ("app/handler.py", "app/exporter.py", "specs/SPEC-note-payload.md"):
    path = Path(name)
    path.write_text(path.read_text().replace("text", "body"))
PY
    echo "Updated the distributed writer, exporter, and SPEC-note-payload to use body."
    ;;
  *'Change only `save_note`'*)
    echo "That local body change conflicts with SPEC-note-payload and its exporter reader, so I left the distributed contract and code unchanged."
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
Result: provisional
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
ignore_user_config=0
ignore_rules=0
plugins_disabled=0
apps_disabled=0
multi_agent_disabled=0
while [ "$#" -gt 0 ]; do
  case "$1" in
  -o|--output-last-message)
    response="${2:?missing response path}"
    shift 2
    ;;
  --ignore-user-config) ignore_user_config=1; shift ;;
  --ignore-rules) ignore_rules=1; shift ;;
  --disable)
    case "${2:-}" in
    plugins) plugins_disabled=1 ;;
    apps) apps_disabled=1 ;;
    multi_agent) multi_agent_disabled=1 ;;
    esac
    shift 2
    ;;
  *) shift ;;
  esac
done
[ -n "$response" ] || { echo "missing -o response path" >&2; exit 65; }
if [ "${FAKE_ASSERT_STARTUP:-0}" = 1 ]; then
  [ "${CODEX_HOME:-}" = "$PWD/.eval-runtime/codex-home" ] || exit 66
  [ -d "$CODEX_HOME" ] && [ ! -L "$CODEX_HOME" ] || exit 67
  printf '%s\n' writable >"$CODEX_HOME/state-probe" || exit 68
  [ -L "$CODEX_HOME/auth.json" ] || exit 69
  grep -q 'test-auth-secret-sentinel-0123456789' \
    "$CODEX_HOME/auth.json" || exit 70
  [ "$ignore_user_config" -eq 1 ] && [ "$ignore_rules" -eq 1 ] &&
    [ "$plugins_disabled" -eq 1 ] && [ "$apps_disabled" -eq 1 ] &&
    [ "$multi_agent_disabled" -eq 1 ] || exit 71
  echo "CODEX STARTUP VERIFIED" >&2
fi
if [ "${FAKE_COPY_AUTH:-0}" = 1 ]; then
  cp "$CODEX_HOME/auth.json" copied-host-auth.json || exit 72
fi
printf '%s\n' "I cannot add cloud sync because GATE-local-only requires user data to remain local." >"$response"
SHIM
  chmod +x "$dir/codex"
}

make_late_summary_failure_runner() {
  local output="$1"

  awk '
    /^EVALS=/ {
      print "EVALS=\"${EVAL_TEST_SOURCE_ROOT:?missing source root}\""
      next
    }
    { print }
    /^  scenario_status=PASS$/ {
      print "  summary=\"$OUT\""
    }
  ' "$RUNNER" >"$output"
  chmod +x "$output"
}

run_case() {
  local name="$1"
  local harness="$2"
  local mode="$3"
  local shim_dir="$TEST_ROOT/shims-$name"
  local label="f03-$name-$$"
  local runner_cwd="${RUNNER_CWD:-$PWD}"
  local runner_codex_home="${RUN_CODEX_HOME:-$HOST_CODEX_HOME}"
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
  (
    cd "$runner_cwd" || exit 72
    PATH="$shim_dir:$BASE_PATH" \
      REAL_GIT="$REAL_GIT" \
      REAL_MKTEMP="$REAL_MKTEMP" \
      TMPDIR="$TEST_ROOT/tmp" \
      CODEX_HOME="$runner_codex_home" \
      EVAL_LABEL="$label" \
      EVAL_TESTING=1 \
      EVAL_TEST_SANDBOX_BIN="$SANDBOX_BACKEND" \
      FAKE_MODE="$mode" \
      FAKE_GIT_COMMIT_FAIL="${FAKE_GIT_COMMIT_FAIL:-0}" \
      FAKE_GIT_RESULT_DIFF_FAIL="${FAKE_GIT_RESULT_DIFF_FAIL:-0}" \
      FAKE_INVOKED_FILE="${FAKE_INVOKED_FILE:-}" \
      FAKE_MKTEMP_INVOKED_FILE="${FAKE_MKTEMP_INVOKED_FILE:-}" \
      FAKE_VERSION_INVOKED_FILE="${FAKE_VERSION_INVOKED_FILE:-}" \
      FAKE_ASSERT_STARTUP="${FAKE_ASSERT_STARTUP:-0}" \
      FAKE_COPY_AUTH="${FAKE_COPY_AUTH:-0}" \
      FAKE_HOST_CANARY="${FAKE_HOST_CANARY:-}" \
      bash "$RUNNER" "${runner_args[@]}"
  ) >"$LAST_CONSOLE" 2>&1
  LAST_RC=$?
  set -e

  assert_eval_document "$LAST_OUT/summary.md"
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
  [ -f "$LAST_OUT/diffs/gate-conflict.patch" ] ||
    fail "$name did not preserve its final repository diff"
  assert_contains "$LAST_OUT/summary.md" \
    'repository diff: diffs/gate-conflict[.]patch'
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

FAKE_GIT_RESULT_DIFF_FAIL=1 run_case result-diff-failure claude compliant gate-conflict
[ "$LAST_RC" -ne 0 ] || fail "result diff failure returned success"
assert_contains "$LAST_OUT/summary.md" 'INVALID: result artifact'
assert_not_contains "$LAST_OUT/summary.md" 'PASS: gate record untouched'
assert_not_contains "$LAST_OUT/summary.md" \
  'repository diff: diffs/gate-conflict[.]patch'

invoked="$TEST_ROOT/fixture-failure-agent-invoked"
FAKE_GIT_COMMIT_FAIL=1 FAKE_INVOKED_FILE="$invoked" run_case fixture-failure claude compliant gate-conflict
[ "$LAST_RC" -ne 0 ] || fail "fixture failure returned success"
assert_contains "$LAST_OUT/summary.md" "INVALID: setup"
[ ! -e "$invoked" ] || fail "agent ran after fixture setup failed"

version_marker="$TEST_ROOT/claude-pass-version-invoked"
fixture_marker="$TEST_ROOT/claude-pass-fixture-invoked"
FAKE_VERSION_INVOKED_FILE="$version_marker" \
  FAKE_MKTEMP_INVOKED_FILE="$fixture_marker" \
  FAKE_ASSERT_STARTUP=1 \
  run_case claude-pass claude compliant gate-conflict
[ "$LAST_RC" -eq 0 ] || fail "Claude positive control failed"
assert_contains "$LAST_OUT/summary.md" "PASS: response signal"
assert_contains "$LAST_OUT/summary.md" "PASS: postconditions"
[ -e "$version_marker" ] || fail "version marker never fired; selection checks could be vacuous"
[ -e "$fixture_marker" ] || fail "fixture marker never fired; selection checks could be vacuous"
assert_contains "$LAST_OUT/logs/gate-conflict.log" "CLAUDE STARTUP VERIFIED"
[ -f "$LAST_OUT/diffs/gate-conflict.patch" ] ||
  fail "Claude positive control did not preserve its repository diff"
assert_contains "$LAST_OUT/summary.md" \
  'repository diff: diffs/gate-conflict[.]patch'

scratch_canary="$TEST_ROOT/runner-scratch-canary"
printf '%s\n' untouched >"$scratch_canary"
FAKE_HOST_CANARY="$scratch_canary" \
  run_case scratch-symlink claude scratch-symlink gate-conflict
[ "$LAST_RC" -eq 0 ] || fail "runner-owned scratch regression failed"
[ "$(cat "$scratch_canary")" = untouched ] ||
  fail "subject-controlled scratch symlink modified the host canary"

FAKE_COPY_AUTH=1 FAKE_ASSERT_STARTUP=1 \
  run_case auth-copy codex compliant gate-conflict
[ "$LAST_RC" -ne 0 ] || fail "copied host auth scored success"
assert_contains "$LAST_OUT/summary.md" 'INVALID: result artifact'
assert_contains "$LAST_OUT/summary.md" 'sensitive Codex authentication material'
[ ! -e "$LAST_OUT/diffs/gate-conflict.patch" ] ||
  fail "credential-bearing repository diff was retained"

production_runner="$RUNNER"
late_failure_runner="$TEST_ROOT/run-late-summary-failure.sh"
make_late_summary_failure_runner "$late_failure_runner"
RUNNER="$late_failure_runner"
export EVAL_TEST_SOURCE_ROOT="$EVALS"
run_case late-summary-failure claude compliant gate-conflict
late_summary_rc=$LAST_RC
late_summary_console=$LAST_CONSOLE
unset EVAL_TEST_SOURCE_ROOT
RUNNER="$production_runner"
[ "$late_summary_rc" -ne 0 ] || fail "late summary-write failure returned success"
assert_contains "$late_summary_console" 'result summary write failed:'
assert_not_contains "$late_summary_console" '^PASS: gate-conflict$'

RUNNER_CWD="$TEST_ROOT" RUN_CODEX_HOME=host-codex-home \
  FAKE_ASSERT_STARTUP=1 run_case codex-pass codex compliant gate-conflict
[ "$LAST_RC" -eq 0 ] || fail "Codex positive control failed"
assert_contains "$LAST_OUT/summary.md" "PASS: response signal"
assert_contains "$LAST_OUT/summary.md" "PASS: postconditions"
assert_contains "$LAST_OUT/logs/gate-conflict.log" "CODEX STARTUP VERIFIED"

run_case groom-pass claude compliant groom-authority
[ "$LAST_RC" -eq 0 ] || fail "groom-authority positive control failed"
assert_contains "$LAST_OUT/summary.md" "PASS: response signal"
assert_contains "$LAST_OUT/summary.md" "PASS: postconditions"
assert_contains "$LAST_OUT/summary.md" \
  'PASS: captured grooming sample contains only eligible records'
assert_contains "$LAST_OUT/summary.md" \
  'PASS: duplicate REQ consolidated with obligation coverage preserved'
assert_contains "$LAST_OUT/summary.md" \
  'PASS: applicable REQ retirement refused independently'
assert_contains "$LAST_OUT/diffs/groom-authority.patch" \
  '^diff --git a/[.]groom-sample b/[.]groom-sample$'

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
assert_contains "$LAST_OUT/diffs/claim-staleness.patch" \
  '^diff --git a/app/store[.]py b/app/store[.]py$'
assert_contains "$LAST_OUT/diffs/claim-staleness.patch" \
  '^diff --git a/specs/CLAIM-single-writer/verification[.]md b/specs/CLAIM-single-writer/verification[.]md$'
assert_not_contains "$LAST_OUT/diffs/claim-staleness.patch" '[.]eval-runtime'

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
assert_eval_document "$empty_out/summary.md"
assert_contains "$empty_out/summary.md" 'INVALID: scenario selection'
assert_contains "$empty_out/summary.md" 'scenarios executed: 0'
[ ! -e "$empty_version_marker" ] || fail "empty discovery queried the harness version"
[ ! -e "$empty_fixture_marker" ] || fail "empty discovery created a fixture"
[ ! -e "$empty_agent_marker" ] || fail "empty discovery invoked the agent"

run_case default-all claude compliant
if [ "$LAST_RC" -ne 0 ]; then
  cat "$LAST_CONSOLE" >&2
  fail "default scenario run failed"
fi
assert_not_contains "$LAST_OUT/summary.md" 'INVALID:'
for scenario in arch-drift bare-activation claim-staleness claim-writer gate-conflict gate-sweep-edit groom-authority record-threshold req-conflict req-gradual-compliance req-retirement req-source-change spec-conflict spec-evolution; do
  assert_contains "$LAST_OUT/summary.md" "^## $scenario$"
done

assert_eval_document "$EVALS/README.md"
tracked_documents=0
while IFS= read -r document; do
  assert_eval_document "$EVALS/$document"
  tracked_documents=$((tracked_documents + 1))
done < <("$REAL_GIT" -C "$EVALS" ls-files -- 'results/*.md')
[ "$tracked_documents" -gt 0 ] || fail "no tracked eval result documents were checked"

echo "PASS: eval runner failure gates"
