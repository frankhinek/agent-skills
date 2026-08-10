#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO/vendor.sh"
SYSTEM_BASH="${SYSTEM_BASH:-/bin/bash}"
REAL_CP="$(type -P cp)"
REAL_FIND="$(type -P find)"
REAL_MKDIR="$(type -P mkdir)"
REAL_MV="$(type -P mv)"
REAL_RM="$(type -P rm)"
REAL_GIT="$(type -P git)"
ORIGINAL_PATH="$PATH"
UNREACHABLE_BIN="$REPO/tests/fixtures/git-unreachable"
TEST_PARENT="${TMPDIR:-/tmp}"
TEST_ROOT="$(mktemp -d "$TEST_PARENT/linked-records-vendor-transaction.XXXXXX")"
PROJECTS="$TEST_ROOT/projects"
SNAPSHOTS="$TEST_ROOT/snapshots"
TRANSACTION_RELATIVE=".agents/.vendor-transaction"
INITIALIZING_RELATIVE="${TRANSACTION_RELATIVE}.initializing"

unset BASH_ENV ENV
unset -f cp 2>/dev/null || true
unset -f mkdir 2>/dev/null || true
unset -f mv 2>/dev/null || true
unset -f rm 2>/dev/null || true

cleanup() {
  case "$TEST_ROOT" in
  "$TEST_PARENT/linked-records-vendor-transaction."*)
    "$REAL_RM" -rf -- "$TEST_ROOT"
    ;;
  *) echo "refusing to clean unexpected test root: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local name="$1"
  local output="$2"
  local expected="$3"
  printf '%s\n' "$output" | grep -Fq -- "$expected" ||
    fail "$name omitted '$expected': $output"
}

assert_omits() {
  local name="$1"
  local output="$2"
  local unexpected="$3"
  if printf '%s\n' "$output" | grep -Fq -- "$unexpected"; then
    fail "$name unexpectedly printed '$unexpected': $output"
  fi
}

run_vendor() {
  local path_prefix="$1"
  shift
  set +e
  if [ -n "$path_prefix" ]; then
    RUN_OUTPUT="$(PATH="$path_prefix:$UNREACHABLE_BIN:$ORIGINAL_PATH" \
      VENDOR_TEST_REAL_GIT="$REAL_GIT" "$SYSTEM_BASH" "$VENDOR" "$@" 2>&1)"
  else
    RUN_OUTPUT="$(PATH="$UNREACHABLE_BIN:$ORIGINAL_PATH" \
      VENDOR_TEST_REAL_GIT="$REAL_GIT" "$SYSTEM_BASH" "$VENDOR" "$@" 2>&1)"
  fi
  RUN_STATUS=$?
  set -e
}

mode_bits() {
  local path="$1"
  local mode
  if mode="$(stat -f '%Lp' "$path" 2>/dev/null)"; then
    :
  else
    mode="$(stat -c '%a' "$path")"
  fi
  printf '%s\n' "$mode"
}

snapshot_skills() {
  local root="$1"
  local output="$2"
  (
    cd "$root"
    if [ ! -e .agents/skills ] && [ ! -L .agents/skills ]; then
      printf '%s\n' absent
      exit
    fi
    find .agents/skills -print0 | while IFS= read -r -d '' path; do
      if [ -L "$path" ]; then
        printf 'l %s -> %s\n' "$path" "$(readlink "$path")"
      elif [ -d "$path" ]; then
        printf 'd %s\n' "$path"
      elif [ -f "$path" ]; then
        read -r checksum size < <(cksum <"$path")
        printf 'f %s %s %s %s\n' \
          "$path" "$(mode_bits "$path")" "$checksum" "$size"
      else
        printf 'u %s\n' "$path"
      fi
    done | LC_ALL=C sort
  ) >"$output"
}

assert_same_snapshot() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  cmp -s "$expected" "$actual" || {
    diff -u "$expected" "$actual" >&2 || true
    fail "$name changed the managed payload or manifest"
  }
}

assert_no_transaction() {
  local name="$1"
  local root="$2"
  [ ! -e "$root/$TRANSACTION_RELATIVE" ] &&
    [ ! -L "$root/$TRANSACTION_RELATIVE" ] ||
    fail "$name left a vendor transaction artifact"
}

set_offline_remote() {
  local manifest="$1"
  awk -v remote="https://github.com/example/unreachable-fixture" '
    /^# vendored-from:/ { print "# vendored-from: " remote; next }
    { print }
  ' "$manifest" >"$manifest.tmp"
  "$REAL_MV" "$manifest.tmp" "$manifest"
}

make_copy_project() {
  local name="$1"
  local root="$PROJECTS/$name"
  mkdir -p "$root"
  "$SYSTEM_BASH" "$VENDOR" --copy "$root" >/dev/null
  set_offline_remote "$root/.agents/skills/.vendored-manifest"
  mkdir -p "$root/.agents/skills/unrelated-skill"
  printf '%s\n' 'preserve me' >"$root/.agents/skills/unrelated-skill/KEEP"
  printf '%s\n' "$root"
}

make_cp_shim() {
  local name="$1"
  local behavior="$2"
  local shim="$TEST_ROOT/$name-shim"
  local marker="$TEST_ROOT/$name.triggered"
  mkdir -p "$shim"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'marker=%q\n' "$marker"
    printf 'real_cp=%q\n' "$REAL_CP"
    printf 'behavior=%q\n' "$behavior"
    printf '%s\n' \
      'for arg in "$@"; do' \
      '  case "$arg" in' \
      '  */skills/linked-records-claims)' \
      '    : >"$marker"' \
      '    if [ "$behavior" = fail ]; then exit 71; fi' \
      '    exit 0' \
      '    ;;' \
      '  esac' \
      'done' \
      'exec "$real_cp" "$@"'
  } >"$shim/cp"
  chmod +x "$shim/cp"
  printf '%s\n' "$shim"
}

make_mv_shim() {
  local name="$1"
  local behavior="$2"
  local skill="$3"
  local shim="$TEST_ROOT/$name-shim"
  local marker="$TEST_ROOT/$name.triggered"
  mkdir -p "$shim"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'marker=%q\n' "$marker"
    printf 'real_mv=%q\n' "$REAL_MV"
    printf 'behavior=%q\n' "$behavior"
    printf 'skill=%q\n' "$skill"
    printf '%s\n' \
      'argc=$#' \
      'eval "source_arg=\${$((argc - 1))}"' \
      'eval "target_arg=\${$argc}"' \
      'case "$source_arg:$target_arg" in' \
      '*/.vendor-transaction/stage/"$skill":.agents/skills/"$skill")' \
      '  : >"$marker"' \
      '  if [ "$behavior" = fail ]; then exit 76; fi' \
      '  "$real_mv" "$@"' \
      '  if [ "$behavior" = term ]; then' \
      '    /bin/kill -TERM "$PPID"' \
      '    exit 143' \
      '  fi' \
      '  /bin/kill -KILL "$PPID"' \
      '  exit 137' \
      '  ;;' \
      'esac' \
      'exec "$real_mv" "$@"'
  } >"$shim/mv"
  chmod +x "$shim/mv"
  printf '%s\n' "$shim"
}

make_manifest_kill_shim() {
  local name="$1"
  local target="$2"
  local shim="$TEST_ROOT/$name-shim"
  local marker="$TEST_ROOT/$name.triggered"
  mkdir -p "$shim"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'marker=%q\n' "$marker"
    printf 'real_mv=%q\n' "$REAL_MV"
    printf 'target=%q\n' "$target"
    printf '%s\n' \
      'argc=$#' \
      'eval "source_arg=\${$((argc - 1))}"' \
      'eval "target_arg=\${$argc}"' \
      'case "$target:$source_arg:$target_arg" in' \
      'manifest:*/.vendor-transaction/prepared-manifest:.agents/skills/.vendored-manifest)' \
      '  : >"$marker"' \
      '  "$real_mv" "$@"' \
      '  /bin/kill -KILL "$PPID"' \
      '  exit 137' \
      '  ;;' \
      'committed:*/.vendor-transaction/phase.new:.agents/.vendor-transaction/phase)' \
      '  "$real_mv" "$@"' \
      '  if [ "$(sed -n "1p" "$target_arg")" = committed ]; then' \
      '    : >"$marker"' \
      '    /bin/kill -KILL "$PPID"' \
      '    exit 137' \
      '  fi' \
      '  exit 0' \
      '  ;;' \
      'esac' \
      'exec "$real_mv" "$@"'
  } >"$shim/mv"
  chmod +x "$shim/mv"
  printf '%s\n' "$shim"
}

make_init_signal_shim() {
  local name="$1" shim="$TEST_ROOT/$1-shim" marker="$TEST_ROOT/$1.triggered"
  mkdir -p "$shim"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'marker=%q\nreal_mkdir=%q\n' "$marker" "$REAL_MKDIR"
    printf '%s\n' \
      'if [ "$#" -eq 1 ] && [ "$1" = .agents/.vendor-transaction.initializing ]; then' \
      '  "$real_mkdir" "$1"' \
      '  : >"$marker"' \
      '  /bin/kill -KILL "$PPID"' \
      '  exit 137' \
      'fi' \
      'exec "$real_mkdir" "$@"'
  } >"$shim/mkdir"
  chmod +x "$shim/mkdir"
  printf '%s\n' "$shim"
}

make_live_inventory_shim() {
  local name="$1"
  local shim="$TEST_ROOT/$name-shim"
  local marker="$TEST_ROOT/$name.triggered"
  local state="$TEST_ROOT/$name.count"
  mkdir -p "$shim"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'marker=%q\n' "$marker"
    printf 'state=%q\n' "$state"
    printf 'real_find=%q\n' "$REAL_FIND"
    printf '%s\n' \
      'if [ "${1:-}" = ".agents/skills/linked-records" ]; then' \
      '  count=0' \
      '  [ ! -f "$state" ] || read -r count <"$state"' \
      '  count=$((count + 1))' \
      '  printf "%s\n" "$count" >"$state"' \
      '  if [ "$count" -eq 2 ]; then' \
      '    : >"$marker"' \
      '    echo "forced live inventory failure" >&2' \
      '    exit 75' \
      '  fi' \
      'fi' \
      'exec "$real_find" "$@"'
  } >"$shim/find"
  chmod +x "$shim/find"
  printf '%s\n' "$shim"
}

assert_triggered() {
  local name="$1"
  [ -f "$TEST_ROOT/$name.triggered" ] || fail "$name shim did not trigger"
}

mkdir -p "$PROJECTS" "$SNAPSHOTS"

# A normal forced refresh replaces local changes and publishes a matching manifest.
normal_project="$(make_copy_project normal-refresh)"
printf '%s\n' 'local marker' >>"$normal_project/.agents/skills/linked-records/SKILL.md"
run_vendor "" --copy --force "$normal_project"
[ "$RUN_STATUS" -eq 0 ] || fail "normal refresh failed: $RUN_OUTPUT"
if grep -Fq 'local marker' "$normal_project/.agents/skills/linked-records/SKILL.md"; then
  fail "normal refresh retained overwritten content"
fi
assert_no_transaction normal-refresh "$normal_project"
set_offline_remote "$normal_project/.agents/skills/.vendored-manifest"
run_vendor "" --check "$normal_project"
[ "$RUN_STATUS" -eq 0 ] || fail "normal refreshed copy did not check clean: $RUN_OUTPUT"
assert_contains normal-check "$RUN_OUTPUT" "local edits: none"

# Copy command failure is contained entirely in staging.
cp_failure_project="$(make_copy_project cp-failure)"
snapshot_skills "$cp_failure_project" "$SNAPSHOTS/cp-failure.before"
cp_failure_shim="$(make_cp_shim cp-failure fail)"
run_vendor "$cp_failure_shim" --copy "$cp_failure_project"
[ "$RUN_STATUS" -ne 0 ] || fail "cp failure unexpectedly succeeded"
assert_triggered cp-failure
assert_contains cp-failure "$RUN_OUTPUT" "existing installation is unchanged"
snapshot_skills "$cp_failure_project" "$SNAPSHOTS/cp-failure.after"
assert_same_snapshot cp-failure "$SNAPSHOTS/cp-failure.before" \
  "$SNAPSHOTS/cp-failure.after"
assert_no_transaction cp-failure "$cp_failure_project"

# A successful cp that silently omits one skill is caught by source/stage inventory.
silent_project="$(make_copy_project silent-stage)"
snapshot_skills "$silent_project" "$SNAPSHOTS/silent.before"
silent_shim="$(make_cp_shim silent-stage silent)"
run_vendor "$silent_shim" --copy "$silent_project"
[ "$RUN_STATUS" -ne 0 ] || fail "silent incomplete stage unexpectedly succeeded"
assert_triggered silent-stage
assert_contains silent-stage "$RUN_OUTPUT" "staged copy does not match source inventory"
snapshot_skills "$silent_project" "$SNAPSHOTS/silent.after"
assert_same_snapshot silent-stage "$SNAPSHOTS/silent.before" \
  "$SNAPSHOTS/silent.after"
assert_no_transaction silent-stage "$silent_project"

# A catchable rename failure after commit starts restores old payload and manifest.
rename_project="$(make_copy_project rename-failure)"
snapshot_skills "$rename_project" "$SNAPSHOTS/rename.before"
rename_shim="$(make_mv_shim rename-failure fail linked-records-claims)"
run_vendor "$rename_shim" --copy "$rename_project"
[ "$RUN_STATUS" -ne 0 ] || fail "rename failure unexpectedly succeeded"
assert_triggered rename-failure
assert_contains rename-failure "$RUN_OUTPUT" "restored previous installation"
snapshot_skills "$rename_project" "$SNAPSHOTS/rename.after"
assert_same_snapshot rename-failure "$SNAPSHOTS/rename.before" \
  "$SNAPSHOTS/rename.after"
assert_no_transaction rename-failure "$rename_project"

# A live verification failure after all swaps restores the old installation.
verify_project="$(make_copy_project live-inventory-failure)"
snapshot_skills "$verify_project" "$SNAPSHOTS/verify.before"
verify_shim="$(make_live_inventory_shim live-inventory-failure)"
run_vendor "$verify_shim" --copy "$verify_project"
[ "$RUN_STATUS" -ne 0 ] || fail "live inventory failure unexpectedly succeeded"
assert_triggered live-inventory-failure
assert_contains live-inventory-failure "$RUN_OUTPUT" "forced live inventory failure"
assert_contains live-inventory-failure "$RUN_OUTPUT" "restored previous installation"
snapshot_skills "$verify_project" "$SNAPSHOTS/verify.after"
assert_same_snapshot live-inventory-failure "$SNAPSHOTS/verify.before" \
  "$SNAPSHOTS/verify.after"
assert_no_transaction live-inventory-failure "$verify_project"

# A catchable signal after a live rename runs the same rollback path.
signal_project="$(make_copy_project term-signal)"
snapshot_skills "$signal_project" "$SNAPSHOTS/signal.before"
signal_shim="$(make_mv_shim term-signal term linked-records)"
run_vendor "$signal_shim" --copy "$signal_project"
[ "$RUN_STATUS" -ne 0 ] || fail "TERM-interrupted refresh unexpectedly succeeded"
assert_triggered term-signal
assert_contains term-signal "$RUN_OUTPUT" "vendor transaction interrupted by TERM"
snapshot_skills "$signal_project" "$SNAPSHOTS/signal.after"
assert_same_snapshot term-signal "$SNAPSHOTS/signal.before" \
  "$SNAPSHOTS/signal.after"
assert_no_transaction term-signal "$signal_project"

# An uncatchable initialization interruption leaves only private state. The
# next mutation removes it without touching the installed payload.
init_project="$(make_copy_project init-signal)"
snapshot_skills "$init_project" "$SNAPSHOTS/init.before"
init_shim="$(make_init_signal_shim init-signal)"
run_vendor "$init_shim" --copy "$init_project"
[ "$RUN_STATUS" -ne 0 ] || fail "initialization signal unexpectedly succeeded"
assert_triggered init-signal
[ -d "$init_project/$INITIALIZING_RELATIVE" ] ||
  fail "initialization kill did not retain private initialization state"
snapshot_skills "$init_project" "$SNAPSHOTS/init.after"
assert_same_snapshot init-signal "$SNAPSHOTS/init.before" "$SNAPSHOTS/init.after"
assert_no_transaction init-signal "$init_project"
run_vendor "" --check "$init_project"
[ "$RUN_STATUS" -eq 1 ] || fail "initialization check returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains init-check "$RUN_OUTPUT" "incomplete vendor transaction initialization"
[ -d "$init_project/$INITIALIZING_RELATIVE" ] ||
  fail "initialization check mutated private state"
run_vendor "" --copy "$init_project"
[ "$RUN_STATUS" -eq 1 ] || fail "initialization recovery returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains init-recovery "$RUN_OUTPUT" "Removed an abandoned vendor transaction initialization"
[ ! -e "$init_project/$INITIALIZING_RELATIVE" ] ||
  fail "initialization recovery retained private state"
snapshot_skills "$init_project" "$SNAPSHOTS/init.recovered"
assert_same_snapshot init-recovery "$SNAPSHOTS/init.before" "$SNAPSHOTS/init.recovered"

# SIGKILL after one live activation leaves durable state; check is read-only,
# the next mutation restores without --force, and a final rerun succeeds.
kill_project="$(make_copy_project hard-kill)"
snapshot_skills "$kill_project" "$SNAPSHOTS/kill.before"
kill_shim="$(make_mv_shim hard-kill kill linked-records)"
run_vendor "$kill_shim" --copy "$kill_project"
[ "$RUN_STATUS" -ne 0 ] || fail "hard-kill refresh unexpectedly succeeded"
assert_triggered hard-kill
[ -d "$kill_project/$TRANSACTION_RELATIVE" ] ||
  fail "hard kill did not retain transaction state"
[ ! -e "$kill_project/.agents/skills/.vendored-manifest" ] ||
  fail "hard kill retained the public old manifest after live mutation began"
snapshot_skills "$kill_project" "$SNAPSHOTS/kill.interrupted"
run_vendor "" --check "$kill_project"
[ "$RUN_STATUS" -eq 1 ] || fail "interrupted check returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains hard-kill-check "$RUN_OUTPUT" "incomplete vendor updater transaction"
assert_omits hard-kill-check "$RUN_OUTPUT" "local edits:"
assert_omits hard-kill-check "$RUN_OUTPUT" "--force"
snapshot_skills "$kill_project" "$SNAPSHOTS/kill.checked"
assert_same_snapshot hard-kill-check "$SNAPSHOTS/kill.interrupted" \
  "$SNAPSHOTS/kill.checked"
run_vendor "" --copy "$kill_project"
[ "$RUN_STATUS" -eq 1 ] || fail "hard-kill recovery returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains hard-kill-recovery "$RUN_OUTPUT" "restored previous installation"
assert_contains hard-kill-recovery "$RUN_OUTPUT" "Re-run vendor.sh"
assert_omits hard-kill-recovery "$RUN_OUTPUT" "--force"
snapshot_skills "$kill_project" "$SNAPSHOTS/kill.restored"
assert_same_snapshot hard-kill-recovery "$SNAPSHOTS/kill.before" \
  "$SNAPSHOTS/kill.restored"
assert_no_transaction hard-kill-recovery "$kill_project"
run_vendor "" --copy "$kill_project"
[ "$RUN_STATUS" -eq 0 ] || fail "hard-kill rerun failed: $RUN_OUTPUT"
assert_no_transaction hard-kill-rerun "$kill_project"

# A kill immediately after manifest publication is still a recoverable
# commit-started transaction even though the prepared file has been renamed.
publish_kill_project="$(make_copy_project publish-kill)"
snapshot_skills "$publish_kill_project" "$SNAPSHOTS/publish-kill.before"
publish_kill_shim="$(make_manifest_kill_shim publish-kill manifest)"
run_vendor "$publish_kill_shim" --copy "$publish_kill_project"
[ "$RUN_STATUS" -ne 0 ] || fail "manifest-publication kill unexpectedly succeeded"
assert_triggered publish-kill
run_vendor "" --check "$publish_kill_project"
[ "$RUN_STATUS" -eq 1 ] || fail "publication-kill check returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains publish-kill-check "$RUN_OUTPUT" "incomplete vendor updater transaction"
run_vendor "" --copy "$publish_kill_project"
[ "$RUN_STATUS" -eq 1 ] || fail "publication-kill recovery returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains publish-kill-recovery "$RUN_OUTPUT" "restored previous installation"
snapshot_skills "$publish_kill_project" "$SNAPSHOTS/publish-kill.after"
assert_same_snapshot publish-kill "$SNAPSHOTS/publish-kill.before" \
  "$SNAPSHOTS/publish-kill.after"
assert_no_transaction publish-kill "$publish_kill_project"

# A kill after the committed phase leaves a valid installation that recovery
# verifies before removing transaction artifacts.
committed_project="$(make_copy_project committed-kill)"
committed_shim="$(make_manifest_kill_shim committed-kill committed)"
run_vendor "$committed_shim" --copy "$committed_project"
[ "$RUN_STATUS" -ne 0 ] || fail "committed-phase kill unexpectedly succeeded"
assert_triggered committed-kill
[ -d "$committed_project/$TRANSACTION_RELATIVE" ] ||
  fail "committed-phase kill did not retain transaction state"
run_vendor "" --copy "$committed_project"
[ "$RUN_STATUS" -eq 1 ] || fail "committed recovery returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains committed-recovery "$RUN_OUTPUT" "Recovered a completed vendor transaction"
assert_no_transaction committed-recovery "$committed_project"
set_offline_remote "$committed_project/.agents/skills/.vendored-manifest"
run_vendor "" --check "$committed_project"
[ "$RUN_STATUS" -eq 0 ] || fail "committed recovery did not check clean: $RUN_OUTPUT"
assert_contains committed-check "$RUN_OUTPUT" "local edits: none"

# A commit-phase failure on a fresh install restores the managed state to absent.
fresh_project="$PROJECTS/fresh-failure"
mkdir -p "$fresh_project/.agents/skills/unrelated-skill"
printf '%s\n' 'preserve me' >"$fresh_project/.agents/skills/unrelated-skill/KEEP"
fresh_shim="$(make_mv_shim fresh-failure fail linked-records-claims)"
run_vendor "$fresh_shim" --copy "$fresh_project"
[ "$RUN_STATUS" -ne 0 ] || fail "fresh rename failure unexpectedly succeeded"
assert_triggered fresh-failure
assert_contains fresh-failure "$RUN_OUTPUT" "restored previous installation"
for skill in linked-records linked-records-claims linked-records-upkeep; do
  [ ! -e "$fresh_project/.agents/skills/$skill" ] ||
    fail "fresh failure left $skill installed"
done
[ ! -e "$fresh_project/.agents/skills/.vendored-manifest" ] ||
  fail "fresh failure left a manifest"
[ "$(sed -n '1p' "$fresh_project/.agents/skills/unrelated-skill/KEEP")" = \
  'preserve me' ] || fail "fresh failure changed the unrelated skill"
assert_no_transaction fresh-failure "$fresh_project"

# A valid pre-commit abandoned transaction is removed, then requires a rerun.
abandoned_project="$(make_copy_project abandoned-precommit)"
abandoned_txn="$abandoned_project/$TRANSACTION_RELATIVE"
mkdir -p "$abandoned_txn/stage" "$abandoned_txn/backup"
printf '%s\n' '1' >"$abandoned_txn/version"
printf '%s\n' 'preparing' >"$abandoned_txn/phase"
printf '%s\n' \
  $'manifest\t1' \
  $'linked-records\t1' \
  $'linked-records-claims\t1' \
  $'linked-records-upkeep\t1' >"$abandoned_txn/original-presence"
run_vendor "" --copy "$abandoned_project"
[ "$RUN_STATUS" -eq 1 ] || fail "abandoned recovery returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains abandoned-precommit "$RUN_OUTPUT" "abandoned pre-commit vendor transaction"
assert_contains abandoned-precommit "$RUN_OUTPUT" "Re-run vendor.sh"
assert_no_transaction abandoned-precommit "$abandoned_project"

# Invalid metadata fails closed for checks and mutations and remains untouched.
malformed_project="$(make_copy_project malformed-transaction)"
malformed_txn="$malformed_project/$TRANSACTION_RELATIVE"
mkdir -p "$malformed_txn"
printf '%s\n' '1' >"$malformed_txn/version"
printf '%s\n' 'unknown-phase' >"$malformed_txn/phase"
printf '%s\n' 'do not remove' >"$malformed_txn/evidence"
snapshot_skills "$malformed_project" "$SNAPSHOTS/malformed.before"
run_vendor "" --check "$malformed_project"
[ "$RUN_STATUS" -eq 1 ] || fail "malformed check returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains malformed-check "$RUN_OUTPUT" "invalid vendor transaction metadata"
assert_omits malformed-check "$RUN_OUTPUT" "local edits:"
assert_omits malformed-check "$RUN_OUTPUT" "--force"
run_vendor "" --copy "$malformed_project"
[ "$RUN_STATUS" -eq 1 ] || fail "malformed refresh returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains malformed-refresh "$RUN_OUTPUT" "invalid vendor transaction metadata"
assert_contains malformed-refresh "$RUN_OUTPUT" "move or remove only that transaction directory"
assert_omits malformed-refresh "$RUN_OUTPUT" "--force"
snapshot_skills "$malformed_project" "$SNAPSHOTS/malformed.after"
assert_same_snapshot malformed-transaction "$SNAPSHOTS/malformed.before" \
  "$SNAPSHOTS/malformed.after"
[ -f "$malformed_txn/evidence" ] || fail "malformed transaction was not retained"

echo "PASS: vendor transaction contract"
