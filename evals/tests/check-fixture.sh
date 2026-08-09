#!/usr/bin/env bash
set -euo pipefail

EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$EVALS/fixture.sh"
REAL_GIT="$(type -P git)"
REAL_RM="$(type -P rm)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/linked-records-check-fixture.XXXXXX")"

unset BASH_ENV ENV
unset -f git rm 2>/dev/null || true

cleanup() {
  case "$TEST_ROOT" in
  "${TMPDIR:-/tmp}/linked-records-check-fixture."*) "$REAL_RM" -rf -- "$TEST_ROOT" ;;
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

assert_complete_fixture() {
  local dest="$1"
  "$REAL_GIT" -C "$dest" rev-parse --verify HEAD >/dev/null 2>&1 ||
    fail "$dest has no valid HEAD"
  [ -z "$("$REAL_GIT" -C "$dest" status --porcelain)" ] ||
    fail "$dest worktree is not clean"
  [ -f "$dest/.agents/skills/linked-records/SKILL.md" ] ||
    fail "$dest lacks vendored linked-records"
  [ -f "$dest/.agents/skills/linked-records-claims/SKILL.md" ] ||
    fail "$dest lacks vendored linked-records-claims"
}

snapshot_dir() {
  local root="$1"
  local output="$2"
  (
    cd "$root"
    find . -type d -print | LC_ALL=C sort | sed 's/^/d /'
    find . -type f -print | LC_ALL=C sort | while IFS= read -r path; do
      printf 'f '
      cksum "$path"
    done
    find . -type l -print | LC_ALL=C sort | while IFS= read -r path; do
      printf 'l %s -> %s\n' "$path" "$(readlink "$path")"
    done
  ) >"$output"
}

expect_rejected() {
  local name="$1"
  shift
  local output="$TEST_ROOT/$name.output"
  set +e
  "$FIXTURE" "$@" >"$output" 2>&1
  REJECT_RC=$?
  set -e
  [ "$REJECT_RC" -ne 0 ] || fail "$name unexpectedly succeeded"
  assert_contains "$output" 'destination must not already exist'
}

mkdir -p "$TEST_ROOT/caller"

absolute_dest="$TEST_ROOT/absolute-fixture"
"$FIXTURE" "$absolute_dest"
assert_complete_fixture "$absolute_dest"

(
  cd "$TEST_ROOT/caller"
  "$FIXTURE" relative-fixture
)
relative_dest="$TEST_ROOT/caller/relative-fixture"
assert_complete_fixture "$relative_dest"

(
  cd "$TEST_ROOT/caller"
  "$FIXTURE" "relative fixture with spaces"
)
spaced_dest="$TEST_ROOT/caller/relative fixture with spaces"
assert_complete_fixture "$spaced_dest"

absolute_tree="$("$REAL_GIT" -C "$absolute_dest" rev-parse 'HEAD^{tree}')"
relative_tree="$("$REAL_GIT" -C "$relative_dest" rev-parse 'HEAD^{tree}')"
spaced_tree="$("$REAL_GIT" -C "$spaced_dest" rev-parse 'HEAD^{tree}')"
[ "$absolute_tree" = "$relative_tree" ] || fail "absolute and relative fixtures differ"
[ "$absolute_tree" = "$spaced_tree" ] || fail "space-containing fixture differs"

existing_dir="$TEST_ROOT/existing-dir"
mkdir -p "$existing_dir/nested"
printf '%s\n' 'keep this directory unchanged' >"$existing_dir/nested/sentinel.txt"
snapshot_dir "$existing_dir" "$TEST_ROOT/existing-dir.before"
expect_rejected existing-dir "$existing_dir"
snapshot_dir "$existing_dir" "$TEST_ROOT/existing-dir.after"
cmp -s "$TEST_ROOT/existing-dir.before" "$TEST_ROOT/existing-dir.after" ||
  fail "existing directory changed"

existing_file="$TEST_ROOT/existing-file"
printf '%s\n' 'keep this file unchanged' >"$existing_file"
cp "$existing_file" "$TEST_ROOT/existing-file.before"
expect_rejected existing-file "$existing_file"
cmp -s "$TEST_ROOT/existing-file.before" "$existing_file" ||
  fail "existing file changed"

symlink_target="$TEST_ROOT/symlink-target"
mkdir -p "$symlink_target"
printf '%s\n' 'keep this target unchanged' >"$symlink_target/sentinel.txt"
symlink_dest="$TEST_ROOT/existing-symlink"
ln -s "$symlink_target" "$symlink_dest"
snapshot_dir "$symlink_target" "$TEST_ROOT/symlink-target.before"
expect_rejected existing-symlink "$symlink_dest"
[ -L "$symlink_dest" ] || fail "existing symlink was replaced"
[ "$(readlink "$symlink_dest")" = "$symlink_target" ] ||
  fail "existing symlink target changed"
snapshot_dir "$symlink_target" "$TEST_ROOT/symlink-target.after"
cmp -s "$TEST_ROOT/symlink-target.before" "$TEST_ROOT/symlink-target.after" ||
  fail "symlink target changed"

make_git_shim() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/git" <<'SHIM'
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = commit ]; then
    case "${FAKE_GIT_MODE:-}" in
    fail)
      echo "simulated fixture commit failure" >&2
      exit 73
      ;;
    term)
      kill -TERM "$PPID"
      exit 0
      ;;
    esac
  fi
done
exec "$REAL_GIT" "$@"
SHIM
  chmod +x "$dir/git"
}

make_rm_shim() {
  local dir="$1"
  cat >"$dir/rm" <<'SHIM'
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = "${FAKE_RM_TARGET:-}" ]; then
    echo "simulated fixture cleanup failure" >&2
    exit 91
  fi
done
exec "$REAL_RM" "$@"
SHIM
  chmod +x "$dir/rm"
}

failure_shims="$TEST_ROOT/failure-shims"
make_git_shim "$failure_shims"
failure_dest="$TEST_ROOT/failure-fixture"
failure_sibling="$TEST_ROOT/failure-sibling"
printf '%s\n' 'keep sibling' >"$failure_sibling"
set +e
PATH="$failure_shims:$PATH" REAL_GIT="$REAL_GIT" FAKE_GIT_MODE=fail \
  "$FIXTURE" "$failure_dest" >"$TEST_ROOT/failure.output" 2>&1
failure_rc=$?
set -e
[ "$failure_rc" -eq 73 ] || fail "setup failure returned $failure_rc instead of 73"
[ ! -e "$failure_dest" ] || fail "failed fixture was not removed"
[ "$(sed -n '1p' "$failure_sibling")" = 'keep sibling' ] ||
  fail "failure cleanup changed an unrelated sibling"

cleanup_shims="$TEST_ROOT/cleanup-shims"
make_git_shim "$cleanup_shims"
make_rm_shim "$cleanup_shims"
cleanup_failure_dest="$TEST_ROOT/cleanup-failure-fixture"
cleanup_failure_physical="$(cd "$(dirname "$cleanup_failure_dest")" && pwd -P)/$(basename "$cleanup_failure_dest")"
set +e
PATH="$cleanup_shims:$PATH" \
  REAL_GIT="$REAL_GIT" \
  REAL_RM="$REAL_RM" \
  FAKE_GIT_MODE=fail \
  FAKE_RM_TARGET="$cleanup_failure_physical" \
  "$FIXTURE" "$cleanup_failure_dest" >"$TEST_ROOT/cleanup-failure.output" 2>&1
cleanup_failure_rc=$?
set -e
[ "$cleanup_failure_rc" -eq 73 ] ||
  fail "cleanup failure replaced original status with $cleanup_failure_rc"
assert_contains "$TEST_ROOT/cleanup-failure.output" 'cleanup failed.*partial fixture remains'
[ -d "$cleanup_failure_dest" ] || fail "cleanup-failure evidence was not retained"
"$REAL_RM" -rf -- "$cleanup_failure_dest"

signal_shims="$TEST_ROOT/signal-shims"
make_git_shim "$signal_shims"
signal_dest="$TEST_ROOT/signal-fixture"
signal_sibling="$TEST_ROOT/signal-sibling"
printf '%s\n' 'keep signal sibling' >"$signal_sibling"
set +e
PATH="$signal_shims:$PATH" REAL_GIT="$REAL_GIT" FAKE_GIT_MODE=term \
  /bin/bash "$FIXTURE" "$signal_dest" >"$TEST_ROOT/signal.output" 2>&1
signal_rc=$?
set -e
[ "$signal_rc" -eq 143 ] || fail "TERM returned $signal_rc instead of 143"
[ ! -e "$signal_dest" ] || fail "TERM left a partial fixture"
[ "$(sed -n '1p' "$signal_sibling")" = 'keep signal sibling' ] ||
  fail "signal cleanup changed an unrelated sibling"

echo "PASS: eval fixture builder"
