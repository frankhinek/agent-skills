#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO/vendor.sh"
REAL_RM="$(type -P rm)"
REAL_FIND="$(type -P find)"
REAL_OD="$(type -P od)"
REAL_STAT="$(type -P stat)"
ORIGINAL_PATH="$PATH"
TEST_PARENT="${TMPDIR:-/tmp}"
TEST_ROOT="$(mktemp -d "$TEST_PARENT/linked-records-vendor-inventory.XXXXXX")"
PROJECTS="$TEST_ROOT/projects"
SNAPSHOTS="$TEST_ROOT/snapshots"

unset BASH_ENV ENV
unset -f rm 2>/dev/null || true
unset -f cksum 2>/dev/null || true
unset -f find 2>/dev/null || true
unset -f od 2>/dev/null || true
unset -f stat 2>/dev/null || true

cleanup() {
  case "$TEST_ROOT" in
  "$TEST_PARENT/linked-records-vendor-inventory."*) "$REAL_RM" -rf -- "$TEST_ROOT" ;;
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
  local vendor="$1"
  shift
  set +e
  RUN_OUTPUT="$(PATH="$ORIGINAL_PATH" "$vendor" "$@" 2>&1)"
  RUN_STATUS=$?
  set -e
}

run_vendor_with_path() {
  local path_prefix="$1"
  local vendor="$2"
  shift 2
  set +e
  RUN_OUTPUT="$(PATH="$path_prefix:$ORIGINAL_PATH" "$vendor" "$@" 2>&1)"
  RUN_STATUS=$?
  set -e
}

set_offline_remote() {
  local manifest="$1"
  awk -v remote="$TEST_ROOT/unreachable-remote" '
    /^# vendored-from:/ { print "# vendored-from: " remote; next }
    { print }
  ' "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
}

make_copy_project() {
  local name="$1"
  local vendor="${2:-$VENDOR}"
  local root="$PROJECTS/$name"
  mkdir -p "$root"
  "$vendor" --copy "$root" >/dev/null
  set_offline_remote "$root/.agents/skills/.vendored-manifest"
  printf '%s\n' "$root"
}

mode_bits() {
  local path="$1"
  local mode
  if mode="$(stat -f '%Lp' "$path" 2>/dev/null)"; then
    :
  elif mode="$(stat -c '%a' "$path" 2>/dev/null)"; then
    :
  else
    return 1
  fi
  printf '%s\n' "$mode"
}

snapshot_tree() {
  local root="$1"
  local output="$2"
  (
    cd "$root"
    find . -print0 | while IFS= read -r -d '' path; do
      if [ -L "$path" ]; then
        printf 'l %s -> %s\n' "$path" "$(readlink "$path")"
      elif [ -d "$path" ]; then
        printf 'd %s\n' "$path"
      elif [ -f "$path" ]; then
        read -r checksum size < <(cksum <"$path")
        printf 'f %s %s %s %s\n' "$path" "$(mode_bits "$path")" "$checksum" "$size"
      elif [ -p "$path" ]; then
        printf 'p %s\n' "$path"
      else
        printf 'u %s\n' "$path"
      fi
    done | LC_ALL=C sort
  ) >"$output"
}

assert_check_change() {
  local name="$1"
  local root="$2"
  shift 2
  snapshot_tree "$root" "$SNAPSHOTS/$name.before"
  run_vendor "$VENDOR" --check "$root"
  [ "$RUN_STATUS" -eq 1 ] ||
    fail "$name check returned $RUN_STATUS instead of 1: $RUN_OUTPUT"
  assert_contains "$name" "$RUN_OUTPUT" "local edits: YES"
  while [ $# -gt 0 ]; do
    assert_contains "$name" "$RUN_OUTPUT" "$1"
    shift
  done
  snapshot_tree "$root" "$SNAPSHOTS/$name.after"
  cmp -s "$SNAPSHOTS/$name.before" "$SNAPSHOTS/$name.after" ||
    fail "$name check changed the project tree"
}

assert_refresh_refused() {
  local name="$1"
  local root="$2"
  local force="${3:-no}"
  snapshot_tree "$root" "$SNAPSHOTS/$name.before"
  if [ "$force" = yes ]; then
    run_vendor "$VENDOR" --copy --force "$root"
  else
    run_vendor "$VENDOR" --copy "$root"
  fi
  [ "$RUN_STATUS" -eq 1 ] ||
    fail "$name refresh returned $RUN_STATUS instead of 1: $RUN_OUTPUT"
  snapshot_tree "$root" "$SNAPSHOTS/$name.after"
  cmp -s "$SNAPSHOTS/$name.before" "$SNAPSHOTS/$name.after" ||
    fail "$name refresh changed the project tree"
}

assert_link_refused() {
  local name="$1"
  local root="$2"
  snapshot_tree "$root" "$SNAPSHOTS/$name.before"
  run_vendor "$VENDOR" --link "$root"
  [ "$RUN_STATUS" -eq 1 ] ||
    fail "$name link returned $RUN_STATUS instead of 1: $RUN_OUTPUT"
  snapshot_tree "$root" "$SNAPSHOTS/$name.after"
  cmp -s "$SNAPSHOTS/$name.before" "$SNAPSHOTS/$name.after" ||
    fail "$name link changed the project tree"
}

assert_inventory_shim_failure() {
  local name="$1"
  local root="$2"
  local shim_dir="$3"
  local diagnostic="$4"

  snapshot_tree "$root" "$SNAPSHOTS/$name.before"
  run_vendor_with_path "$shim_dir" "$VENDOR" --check "$root"
  [ "$RUN_STATUS" -eq 1 ] ||
    fail "$name check returned $RUN_STATUS instead of 1: $RUN_OUTPUT"
  assert_contains "$name-check" "$RUN_OUTPUT" "$diagnostic"
  assert_contains "$name-check" "$RUN_OUTPUT" "local edits: unknown (inventory failed)"
  snapshot_tree "$root" "$SNAPSHOTS/$name.check-after"
  cmp -s "$SNAPSHOTS/$name.before" "$SNAPSHOTS/$name.check-after" ||
    fail "$name check changed the project tree"

  run_vendor_with_path "$shim_dir" "$VENDOR" --copy --force "$root"
  [ "$RUN_STATUS" -eq 1 ] ||
    fail "$name forced refresh returned $RUN_STATUS instead of 1: $RUN_OUTPUT"
  assert_contains "$name-force" "$RUN_OUTPUT" "$diagnostic"
  assert_contains "$name-force" "$RUN_OUTPUT" \
    "cannot safely inventory the existing vendored skills"
  snapshot_tree "$root" "$SNAPSHOTS/$name.force-after"
  cmp -s "$SNAPSHOTS/$name.before" "$SNAPSHOTS/$name.force-after" ||
    fail "$name forced refresh changed the project tree"
}

assert_invalid_format_manifest() {
  local name="$1"
  local root="$2"
  local manifest="$root/.agents/skills/.vendored-manifest"

  run_vendor "$VENDOR" --check "$root"
  [ "$RUN_STATUS" -eq 1 ] ||
    fail "$name check returned $RUN_STATUS instead of 1: $RUN_OUTPUT"
  assert_contains "$name-check" "$RUN_OUTPUT" \
    "local edits: unknown (invalid manifest format)"
  assert_refresh_refused "$name-refresh" "$root"
  run_vendor "$VENDOR" --copy --force "$root"
  [ "$RUN_STATUS" -eq 0 ] || fail "$name forced migration failed: $RUN_OUTPUT"
  [ "$(grep -Fc '# manifest-format: 2' "$manifest")" -eq 1 ] ||
    fail "$name forced migration did not write exactly one format 2 header"
}

mkdir -p "$PROJECTS" "$SNAPSHOTS"

# Executable state changes are local work in both directions.
chmod_remove_project="$(make_copy_project chmod-remove)"
chmod_remove_target="$chmod_remove_project/.agents/skills/linked-records-upkeep/lint.sh"
chmod -x "$chmod_remove_target"
assert_check_change chmod-remove "$chmod_remove_project" \
  "executable changed: .agents/skills/linked-records-upkeep/lint.sh (yes -> no)"
assert_refresh_refused chmod-remove-refresh "$chmod_remove_project"
[ ! -x "$chmod_remove_target" ] || fail "chmod-remove refresh restored executable state"

chmod_add_project="$(make_copy_project chmod-add)"
chmod_add_target="$chmod_add_project/.agents/skills/linked-records/SKILL.md"
chmod +x "$chmod_add_target"
assert_check_change chmod-add "$chmod_add_project" \
  "executable changed: .agents/skills/linked-records/SKILL.md (no -> yes)"
assert_refresh_refused chmod-add-refresh "$chmod_add_project"
[ -x "$chmod_add_target" ] || fail "chmod-add refresh removed executable state"

# Added links, empty directories, type replacements, and renames are inventoried.
link_add_project="$(make_copy_project link-add)"
link_add_path="$link_add_project/.agents/skills/linked-records/local link"
ln -s SKILL.md "$link_add_path"
assert_check_change link-add "$link_add_project" \
  "added: .agents/skills/linked-records/local link (symlink -> SKILL.md)"
assert_refresh_refused link-add-refresh "$link_add_project"
[ -L "$link_add_path" ] || fail "link-add refresh removed the link"

empty_dir_project="$(make_copy_project empty-dir-add)"
mkdir "$empty_dir_project/.agents/skills/linked-records/empty local dir"
assert_check_change empty-dir-add "$empty_dir_project" \
  "added: .agents/skills/linked-records/empty local dir (directory)"

type_project="$(make_copy_project type-change)"
type_path="$type_project/.agents/skills/linked-records-upkeep/lint.sh"
"$REAL_RM" -f -- "$type_path"
mkdir "$type_path"
assert_check_change type-change "$type_project" \
  "type changed: .agents/skills/linked-records-upkeep/lint.sh (file -> directory)"

rename_project="$(make_copy_project rename)"
rename_from="$rename_project/.agents/skills/linked-records-upkeep/tests/check-lint.sh"
rename_to="$rename_project/.agents/skills/linked-records-upkeep/tests/check-lint-renamed.sh"
mv "$rename_from" "$rename_to"
assert_check_change rename "$rename_project" \
  "removed: .agents/skills/linked-records-upkeep/tests/check-lint.sh (file)" \
  "added: .agents/skills/linked-records-upkeep/tests/check-lint-renamed.sh (file)"

# A committed source symlink proves remove and retarget behavior against a real baseline.
SYMLINK_SOURCE="$TEST_ROOT/symlink-source"
git clone --quiet "$REPO" "$SYMLINK_SOURCE"
git -C "$SYMLINK_SOURCE" config user.name "Vendor Inventory Test"
git -C "$SYMLINK_SOURCE" config user.email "vendor-inventory@example.invalid"
git -C "$SYMLINK_SOURCE" config commit.gpgsign false
ln -s SKILL.md "$SYMLINK_SOURCE/skills/linked-records/source-link"
git -C "$SYMLINK_SOURCE" add skills/linked-records/source-link
git -C "$SYMLINK_SOURCE" commit --quiet -m "test: add source symlink"
cp "$VENDOR" "$SYMLINK_SOURCE/vendor.sh"
mkdir -p "$SYMLINK_SOURCE/lib"
cp "$REPO/lib/vendor-inventory.sh" "$SYMLINK_SOURCE/lib/vendor-inventory.sh"

retarget_project="$(make_copy_project link-retarget "$SYMLINK_SOURCE/vendor.sh")"
retarget_path="$retarget_project/.agents/skills/linked-records/source-link"
"$REAL_RM" -f -- "$retarget_path"
ln -s ../linked-records-claims/SKILL.md "$retarget_path"
assert_check_change link-retarget "$retarget_project" \
  "target changed: .agents/skills/linked-records/source-link (SKILL.md -> ../linked-records-claims/SKILL.md)"

link_remove_project="$(make_copy_project link-remove "$SYMLINK_SOURCE/vendor.sh")"
"$REAL_RM" -f -- "$link_remove_project/.agents/skills/linked-records/source-link"
assert_check_change link-remove "$link_remove_project" \
  "removed: .agents/skills/linked-records/source-link (symlink -> SKILL.md)"

# Unsupported live entries fail before mutation, including with --force.
fifo_project="$(make_copy_project fifo)"
fifo_path="$fifo_project/.agents/skills/linked-records/local-fifo"
mkfifo "$fifo_path"
snapshot_tree "$fifo_project" "$SNAPSHOTS/fifo.before"
run_vendor "$VENDOR" --check "$fifo_project"
[ "$RUN_STATUS" -eq 1 ] || fail "FIFO check returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains fifo-check "$RUN_OUTPUT" "unsupported vendored entry: .agents/skills/linked-records/local-fifo (fifo)"
assert_contains fifo-check "$RUN_OUTPUT" "local edits: unknown (inventory failed)"
assert_refresh_refused fifo-refresh "$fifo_project"
assert_refresh_refused fifo-force "$fifo_project" yes
[ -p "$fifo_path" ] || fail "forced FIFO refresh removed the unsupported entry"

# Encoder and per-skill traversal failures propagate out of conditional calls.
encoder_project="$(make_copy_project encoder-failure)"
encoder_shim="$TEST_ROOT/encoder-shim"
mkdir -p "$encoder_shim"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'echo "forced od failure" >&2' 'exit 73'
} >"$encoder_shim/od"
chmod +x "$encoder_shim/od"
assert_inventory_shim_failure encoder-failure "$encoder_project" "$encoder_shim" \
  "cannot encode vendored path"

traversal_project="$(make_copy_project traversal-failure)"
traversal_shim="$TEST_ROOT/traversal-shim"
mkdir -p "$traversal_shim"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' \
    'if [ "${1:-}" = ".agents/skills/linked-records" ]; then' \
    '  echo "forced early find failure" >&2' \
    '  exit 74' \
    'fi'
  printf 'exec "%s" "$@"\n' "$REAL_FIND"
} >"$traversal_shim/find"
chmod +x "$traversal_shim/find"
assert_inventory_shim_failure traversal-failure "$traversal_project" \
  "$traversal_shim" "forced early find failure"

# A successful but non-octal BSD-style probe must fall through to GNU style.
stat_project="$(make_copy_project stat-probe)"
touch "$stat_project/%Lp"
stat_shim="$TEST_ROOT/stat-shim"
mkdir -p "$stat_shim"
if stat_probe="$($REAL_STAT -f '%Lp' "$VENDOR" 2>/dev/null)" &&
  case "$stat_probe" in "" | *[!0-7]*) false ;; *) true ;; esac; then
  real_stat_style=bsd
else
  real_stat_style=gnu
fi
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' \
    'if [ "${1:-}" = "-f" ] && [ "${2:-}" = "%Lp" ]; then' \
    '  echo "fake GNU stat filesystem output"' \
    '  exit 0' \
    'fi'
  if [ "$real_stat_style" = bsd ]; then
    printf '%s\n' \
      'if [ "${1:-}" = "-c" ] && [ "${2:-}" = "%a" ]; then'
    printf '  exec "%s" -f "%%Lp" "$3"\n' "$REAL_STAT"
    printf '%s\n' 'fi'
  fi
  printf 'exec "%s" "$@"\n' "$REAL_STAT"
} >"$stat_shim/stat"
chmod +x "$stat_shim/stat"
run_vendor_with_path "$stat_shim" "$VENDOR" --check "$stat_project"
[ "$RUN_STATUS" -eq 0 ] || fail "stat probe check failed: $RUN_OUTPUT"
assert_contains stat-probe "$RUN_OUTPUT" "local edits: none"

# A post-copy inventory failure leaves the replaced tree without a stale manifest.
post_project="$(make_copy_project post-copy-failure)"
post_target="$post_project/.agents/skills/linked-records/SKILL.md"
printf '%s\n' 'post-copy local marker' >>"$post_target"
post_shim="$TEST_ROOT/post-copy-shim"
post_state="$TEST_ROOT/post-copy-find-count"
mkdir -p "$post_shim"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'state=%q\n' "$post_state"
  printf '%s\n' \
    'count=0' \
    '[ ! -f "$state" ] || read -r count <"$state"' \
    'count=$((count + 1))' \
    'printf "%s\\n" "$count" >"$state"' \
    'if [ "$count" -eq 4 ]; then' \
    '  echo "forced post-copy find failure" >&2' \
    '  exit 75' \
    'fi'
  printf 'exec "%s" "$@"\n' "$REAL_FIND"
} >"$post_shim/find"
chmod +x "$post_shim/find"
run_vendor_with_path "$post_shim" "$VENDOR" --copy --force "$post_project"
[ "$RUN_STATUS" -eq 1 ] ||
  fail "post-copy failure returned $RUN_STATUS instead of 1: $RUN_OUTPUT"
assert_contains post-copy-failure "$RUN_OUTPUT" "forced post-copy find failure"
assert_contains post-copy-failure "$RUN_OUTPUT" \
  "copied skills could not be inventoried; no manifest was written"
[ ! -e "$post_project/.agents/skills/.vendored-manifest" ] ||
  fail "post-copy failure left the old manifest in place"
if grep -Fq 'post-copy local marker' "$post_target"; then
  fail "post-copy failure did not replace the vendored tree"
fi

# Legacy and unknown manifests never claim that the tree is pristine.
legacy_project="$(make_copy_project legacy)"
legacy_manifest="$legacy_project/.agents/skills/.vendored-manifest"
{
  grep '^#' "$legacy_manifest" | grep -v '^# manifest-format:'
  (
    cd "$legacy_project"
    find .agents/skills -type f | LC_ALL=C sort | while IFS= read -r path; do
      cksum "$path"
    done
  )
} >"$legacy_manifest.tmp"
mv "$legacy_manifest.tmp" "$legacy_manifest"
run_vendor "$VENDOR" --check "$legacy_project"
[ "$RUN_STATUS" -eq 1 ] || fail "legacy check returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains legacy-check "$RUN_OUTPUT" "local edits: unknown (legacy manifest format)"
assert_omits legacy-check "$RUN_OUTPUT" "local edits: none"
assert_refresh_refused legacy-refresh "$legacy_project"
assert_link_refused legacy-link "$legacy_project"
run_vendor "$VENDOR" --copy --force "$legacy_project"
[ "$RUN_STATUS" -eq 0 ] || fail "forced legacy migration failed: $RUN_OUTPUT"
grep -Fqx '# manifest-format: 2' "$legacy_manifest" ||
  fail "forced legacy migration did not write manifest format 2"

unknown_project="$(make_copy_project unknown-format)"
unknown_manifest="$unknown_project/.agents/skills/.vendored-manifest"
sed 's/^# manifest-format: 2$/# manifest-format: 99/' "$unknown_manifest" >"$unknown_manifest.tmp"
mv "$unknown_manifest.tmp" "$unknown_manifest"
run_vendor "$VENDOR" --check "$unknown_project"
[ "$RUN_STATUS" -eq 1 ] || fail "unknown-format check returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains unknown-format "$RUN_OUTPUT" "local edits: unknown (unsupported manifest format 99)"
assert_refresh_refused unknown-format-refresh "$unknown_project"
run_vendor "$VENDOR" --copy --force "$unknown_project"
[ "$RUN_STATUS" -eq 0 ] || fail "forced unknown-format migration failed: $RUN_OUTPUT"
grep -Fqx '# manifest-format: 2' "$unknown_manifest" ||
  fail "forced unknown-format migration did not write manifest format 2"

duplicate_project="$(make_copy_project duplicate-format)"
duplicate_manifest="$duplicate_project/.agents/skills/.vendored-manifest"
printf '%s\n' '# manifest-format: 2' >>"$duplicate_manifest"
assert_invalid_format_manifest duplicate-format "$duplicate_project"

conflicting_project="$(make_copy_project conflicting-format)"
conflicting_manifest="$conflicting_project/.agents/skills/.vendored-manifest"
printf '%s\n' '# manifest-format: 99' >>"$conflicting_manifest"
assert_invalid_format_manifest conflicting-format "$conflicting_project"

empty_format_project="$(make_copy_project empty-format)"
empty_format_manifest="$empty_format_project/.agents/skills/.vendored-manifest"
sed 's/^# manifest-format: 2$/# manifest-format:/' "$empty_format_manifest" \
  >"$empty_format_manifest.tmp"
mv "$empty_format_manifest.tmp" "$empty_format_manifest"
assert_invalid_format_manifest empty-format "$empty_format_project"

malformed_project="$(make_copy_project malformed)"
malformed_manifest="$malformed_project/.agents/skills/.vendored-manifest"
printf '%s\n' $'F\tbroken' >>"$malformed_manifest"
run_vendor "$VENDOR" --check "$malformed_project"
[ "$RUN_STATUS" -eq 1 ] || fail "malformed check returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains malformed "$RUN_OUTPUT" "local edits: unknown (invalid manifest inventory)"
assert_refresh_refused malformed-refresh "$malformed_project"

# The emitted v2 body is canonical and a clean copy remains clean.
clean_project="$(make_copy_project clean)"
clean_manifest="$clean_project/.agents/skills/.vendored-manifest"
grep -Fqx '# manifest-format: 2' "$clean_manifest" || fail "manifest omitted format 2 header"
run_vendor "$VENDOR" --check "$clean_project"
[ "$RUN_STATUS" -eq 0 ] || fail "clean check returned $RUN_STATUS: $RUN_OUTPUT"
assert_contains clean "$RUN_OUTPUT" "local edits: none"

echo "PASS: vendor inventory contract"
