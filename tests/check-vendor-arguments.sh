#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO/vendor.sh"
REAL_GIT="$(type -P git)"
REAL_RM="$(type -P rm)"
UNREACHABLE_BIN="$REPO/tests/fixtures/git-unreachable"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/linked-records-vendor-args.XXXXXX")"

unset BASH_ENV ENV
unset -f rm 2>/dev/null || true

cleanup() {
  case "$TEST_ROOT" in
  "${TMPDIR:-/tmp}/linked-records-vendor-args."*) "$REAL_RM" -rf -- "$TEST_ROOT" ;;
  *) echo "refusing to clean unexpected test path: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
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

run_vendor() {
  set +e
  RUN_OUTPUT="$(PATH="$UNREACHABLE_BIN:$PATH" VENDOR_TEST_REAL_GIT="$REAL_GIT" \
    "$VENDOR" "$@" 2>&1)"
  RUN_RC=$?
  set -e
}

assert_check_read_only() {
  local name="$1"
  local root="$2"
  local expected_rc="$3"
  shift 3
  snapshot_dir "$root" "$TEST_ROOT/$name.before"
  run_vendor "$@"
  [ "$RUN_RC" -eq "$expected_rc" ] ||
    fail "$name returned $RUN_RC instead of $expected_rc: $RUN_OUTPUT"
  snapshot_dir "$root" "$TEST_ROOT/$name.after"
  cmp -s "$TEST_ROOT/$name.before" "$TEST_ROOT/$name.after" ||
    fail "$name changed the destination"
  CHECK_OUTPUT="$RUN_OUTPUT"
}

expect_usage_unchanged() {
  local name="$1"
  local root="$2"
  shift 2
  snapshot_dir "$root" "$TEST_ROOT/$name.before"
  run_vendor "$@"
  [ "$RUN_RC" -eq 2 ] || fail "$name returned $RUN_RC instead of usage status 2: $RUN_OUTPUT"
  printf '%s\n' "$RUN_OUTPUT" | grep -Fq 'usage: vendor.sh' ||
    fail "$name omitted the usage diagnostic: $RUN_OUTPUT"
  snapshot_dir "$root" "$TEST_ROOT/$name.after"
  cmp -s "$TEST_ROOT/$name.before" "$TEST_ROOT/$name.after" ||
    fail "$name changed the destination"
}

expect_flag_pair_permutations() {
  local label="$1"
  local first="$2"
  local second="$3"
  local root="$4"
  expect_usage_unchanged "$label-1" "$root" "$first" "$second" "$root"
  expect_usage_unchanged "$label-2" "$root" "$first" "$root" "$second"
  expect_usage_unchanged "$label-3" "$root" "$second" "$first" "$root"
  expect_usage_unchanged "$label-4" "$root" "$second" "$root" "$first"
  expect_usage_unchanged "$label-5" "$root" "$root" "$first" "$second"
  expect_usage_unchanged "$label-6" "$root" "$root" "$second" "$first"
}

assert_mode_force_permutations() {
  local mode="$1"
  local reference_tree=""
  local reference_output=""
  local order root tree
  for order in 1 2 3 4 5 6; do
    root="$TEST_ROOT/$mode-force-$order"
    tree="$TEST_ROOT/$mode-force-$order.tree"
    mkdir -p "$root"
    case "$order" in
    1) run_vendor "--$mode" --force "$root" ;;
    2) run_vendor "--$mode" "$root" --force ;;
    3) run_vendor --force "--$mode" "$root" ;;
    4) run_vendor --force "$root" "--$mode" ;;
    5) run_vendor "$root" "--$mode" --force ;;
    6) run_vendor "$root" --force "--$mode" ;;
    esac
    [ "$RUN_RC" -eq 0 ] || fail "$mode/force permutation $order returned $RUN_RC: $RUN_OUTPUT"
    snapshot_dir "$root" "$tree"
    if [ -z "$reference_tree" ]; then
      reference_tree="$tree"
      reference_output="$RUN_OUTPUT"
    else
      cmp -s "$reference_tree" "$tree" ||
        fail "$mode/force permutation $order produced a different tree"
      [ "$RUN_OUTPUT" = "$reference_output" ] ||
        fail "$mode/force permutation $order produced different output"
    fi
  done
}

linked_project="$TEST_ROOT/linked-project"
mkdir -p "$linked_project"
"$VENDOR" --link "$linked_project" >/dev/null

assert_check_read_only check-before-directory "$linked_project" 0 --check "$linked_project"
before_output="$CHECK_OUTPUT"
assert_check_read_only check-after-directory "$linked_project" 0 "$linked_project" --check
[ "$CHECK_OUTPUT" = "$before_output" ] || fail "check argument orders produced different output"

copy_project="$TEST_ROOT/copy-project"
mkdir -p "$copy_project"
"$VENDOR" "$copy_project" >/dev/null
manifest="$copy_project/.agents/skills/.vendored-manifest"
{
  printf '%s\n' '# vendored-from: https://github.com/example/unreachable-fixture'
  grep -v '^# vendored-from:' "$manifest"
} >"$manifest.tmp"
mv "$manifest.tmp" "$manifest"
assert_check_read_only copied-check-before "$copy_project" 0 --check "$copy_project"
copied_check_output="$CHECK_OUTPUT"
assert_check_read_only copied-check-after "$copy_project" 0 "$copy_project" --check
[ "$CHECK_OUTPUT" = "$copied_check_output" ] ||
  fail "copied check argument orders produced different output"
extra_project="$TEST_ROOT/extra-project"
mkdir -p "$extra_project"
printf '%s\n' 'keep extra project' >"$extra_project/sentinel.txt"

expect_usage_unchanged unknown-before "$linked_project" --unknown "$linked_project"
expect_usage_unchanged unknown-after "$linked_project" "$linked_project" --unknown
expect_usage_unchanged short-unknown "$linked_project" -x "$linked_project"
expect_usage_unchanged extra-directory "$linked_project" "$linked_project" "$extra_project"
[ "$(sed -n '1p' "$extra_project/sentinel.txt")" = 'keep extra project' ] ||
  fail "extra positional directory changed"

expect_flag_pair_permutations copy-link --copy --link "$copy_project"
expect_flag_pair_permutations copy-check --copy --check "$copy_project"
expect_flag_pair_permutations link-check --link --check "$copy_project"
expect_flag_pair_permutations check-force --check --force "$linked_project"

assert_mode_force_permutations copy
assert_mode_force_permutations link

echo "PASS: vendor argument contract"
