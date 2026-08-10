#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_RM="$(type -P rm)"
REAL_GIT="$(type -P git)"
SYSTEM_BASH="${SYSTEM_BASH:-/bin/bash}"
TEST_PARENT="${TMPDIR:-/tmp}"
TEST_ROOT="$(mktemp -d "$TEST_PARENT/linked-records-vendor-staleness.XXXXXX")"
SOURCE="$TEST_ROOT/source"
REMOTE="$TEST_ROOT/published"
PROJECTS="$TEST_ROOT/projects"
SNAPSHOTS="$TEST_ROOT/snapshots"
SKILLS=(linked-records linked-records-claims linked-records-upkeep)

unset BASH_ENV ENV
unset -f git 2>/dev/null || true
unset -f rm 2>/dev/null || true

cleanup() {
  case "$TEST_ROOT" in
  "$TEST_PARENT/linked-records-vendor-staleness."*) "$REAL_RM" -rf -- "$TEST_ROOT" ;;
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

snapshot_tree() {
  local root="$1"
  local output="$2"
  local mode
  (
    cd "$root"
    find . -print0 | while IFS= read -r -d '' path; do
      if [ -L "$path" ]; then
        printf 'l %s -> %s\n' "$path" "$(readlink "$path")"
      elif [ -d "$path" ]; then
        mode="$(mode_bits "$path")"
        printf 'd %s %s\n' "$mode" "$path"
      elif [ -f "$path" ]; then
        mode="$(mode_bits "$path")"
        printf 'f %s ' "$mode"
        cksum "$path"
      else
        printf 'u %s\n' "$path"
      fi
    done | LC_ALL=C sort
  ) >"$output"
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
  case "$mode" in
  "" | *[!0-7]*) return 1 ;;
  esac
  printf '%s\n' "$mode"
}

run_vendor() {
  set +e
  RUN_OUTPUT="$(PATH="${RUN_PATH:-$PATH}" \
    VENDOR_TEST_REAL_GIT="$REAL_GIT" \
    VENDOR_TEST_FORCE_PAYLOAD_READ_FAILURE="${VENDOR_TEST_FORCE_PAYLOAD_READ_FAILURE:-no}" \
    "$SYSTEM_BASH" "$SOURCE/vendor.sh" "$@" 2>&1)"
  RUN_STATUS=$?
  set -e
}

assert_check() {
  local name="$1"
  local project="$2"
  local expected_status="$3"
  shift 3

  snapshot_tree "$project" "$SNAPSHOTS/$name.before"
  run_vendor --check "$project"
  [ "$RUN_STATUS" -eq "$expected_status" ] ||
    fail "$name returned $RUN_STATUS instead of $expected_status: $RUN_OUTPUT"
  snapshot_tree "$project" "$SNAPSHOTS/$name.after"
  cmp -s "$SNAPSHOTS/$name.before" "$SNAPSHOTS/$name.after" ||
    fail "$name changed the project tree"
  while [ "$#" -gt 0 ]; do
    assert_contains "$name" "$RUN_OUTPUT" "$1"
    shift
  done
}

assert_refused_without_mutation() {
  local name="$1"
  local project="$2"
  local expected="$3"

  snapshot_tree "$project" "$SNAPSHOTS/$name.before"
  run_vendor --copy "$project"
  [ "$RUN_STATUS" -eq 1 ] ||
    fail "$name returned $RUN_STATUS instead of 1: $RUN_OUTPUT"
  assert_contains "$name" "$RUN_OUTPUT" "$expected"
  snapshot_tree "$project" "$SNAPSHOTS/$name.after"
  cmp -s "$SNAPSHOTS/$name.before" "$SNAPSHOTS/$name.after" ||
    fail "$name changed the destination"
}

configure_repo() {
  local root="$1"
  mkdir -p "$root/.git-hooks"
  git -C "$root" config user.name "Vendor Staleness Test"
  git -C "$root" config user.email "vendor-staleness@example.invalid"
  git -C "$root" config commit.gpgsign false
  git -C "$root" config core.hooksPath .git-hooks
}

commit_all() {
  local root="$1"
  local message="$2"
  git -C "$root" add -A
  git -C "$root" commit -q -m "$message"
}

make_project() {
  local name="$1"
  local root="$PROJECTS/$name"
  mkdir -p "$root"
  "$SYSTEM_BASH" "$SOURCE/vendor.sh" --copy "$root" >/dev/null
  printf '%s\n' "$root"
}

independent_payload_id() {
  local revision="$1"
  local skill tree

  {
    for skill in "${SKILLS[@]}"; do
      tree="$(git -C "$SOURCE" rev-parse --verify \
        "$revision:skills/$skill")" || return 1
      printf '%s\t%s\n' "$skill" "$tree"
    done
  } | git -C "$SOURCE" hash-object --stdin
}

replace_manifest_header() {
  local manifest="$1"
  local replacement="$2"
  awk -v replacement="$replacement" '
    /^# payload-id:/ { if (!done) print replacement; done = 1; next }
    { print }
  ' "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
}

SHIMS="$TEST_ROOT/shims"
mkdir -p "$SOURCE/lib" "$SOURCE/skills" "$PROJECTS" "$SNAPSHOTS" "$SHIMS"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' 'object_read=no'
  printf '%s\n' 'payload_read=no'
  printf '%s\n' 'for arg in "$@"; do'
  printf '%s\n' '  case "$arg" in'
  printf '%s\n' '    cat-file) object_read=yes ;;'
  printf '%s\n' '    ls-tree) object_read=yes; payload_read=yes ;;'
  printf '%s\n' '  esac'
  printf '%s\n' 'done'
  printf '%s\n' 'if [ "$object_read" = yes ] && [ "${GIT_NO_LAZY_FETCH:-}" != 1 ]; then'
  printf '%s\n' '  echo "managed payload read allowed lazy fetching" >&2'
  printf '%s\n' '  exit 85'
  printf '%s\n' 'fi'
  printf '%s\n' 'if [ "$payload_read" = yes ] &&'
  printf '%s\n' '  [ "${VENDOR_TEST_FORCE_PAYLOAD_READ_FAILURE:-no}" = yes ]; then'
  printf '%s\n' '  exit 86'
  printf '%s\n' 'fi'
  printf '%s\n' 'exec "$VENDOR_TEST_REAL_GIT" "$@"'
} >"$SHIMS/git"
chmod +x "$SHIMS/git"
cp "$REPO/vendor.sh" "$SOURCE/vendor.sh"
cp -R "$REPO/lib/." "$SOURCE/lib/"
for skill in "${SKILLS[@]}"; do
  cp -R "$REPO/skills/$skill" "$SOURCE/skills/$skill"
done
printf '%s\n' '*.ignored' >"$SOURCE/.gitignore"
printf '%s\n' 'fixture repository' >"$SOURCE/README.md"
git -C "$SOURCE" init -q
configure_repo "$SOURCE"
commit_all "$SOURCE" "initial payload"
git init -q --bare "$REMOTE"
git -C "$SOURCE" remote add origin "$REMOTE"
git -C "$SOURCE" push -q -u origin HEAD

initial_revision="$(git -C "$SOURCE" rev-parse HEAD)"
initial_payload="$(independent_payload_id "$initial_revision")"
baseline_project="$(make_project baseline)"
baseline_manifest="$baseline_project/.agents/skills/.vendored-manifest"
manifest_payload="$(sed -n 's/^# payload-id: //p' "$baseline_manifest")"
[ "$manifest_payload" = "$initial_payload" ] ||
  fail "fresh manifest payload ID did not match committed managed trees"

assert_check same-head "$baseline_project" 0 \
  "local edits: none" "published  : current" "managed payload"

printf '%s\n' 'documentation-only change' >>"$SOURCE/README.md"
commit_all "$SOURCE" "docs only"
git -C "$SOURCE" push -q
assert_check unrelated-head "$baseline_project" 0 \
  "local edits: none" "published  : current" "managed payload"
assert_omits unrelated-head "$RUN_OUTPUT" "STALE"

printf '\nmanaged payload change\n' >>"$SOURCE/skills/linked-records/SKILL.md"
commit_all "$SOURCE" "change managed payload"
git -C "$SOURCE" push -q
assert_check changed-payload "$baseline_project" 1 \
  "local edits: none" "published  : STALE" "managed payload"

current_project="$(make_project current)"
remote_work="$TEST_ROOT/remote-work"
git clone -q "$REMOTE" "$remote_work"
configure_repo "$remote_work"
printf '%s\n' 'remote-only documentation change' >>"$remote_work/README.md"
commit_all "$remote_work" "remote-only docs"
git -C "$remote_work" push -q
assert_check unavailable-head "$current_project" 0 \
  "local edits: none" "published  : unknown" "not available locally"
assert_omits unavailable-head "$RUN_OUTPUT" "published  : current"
assert_omits unavailable-head "$RUN_OUTPUT" "published  : STALE"

git -C "$SOURCE" fetch -q origin
git -C "$SOURCE" merge -q --ff-only FETCH_HEAD
missing_skill_backup="$TEST_ROOT/linked-records-claims.backup"
cp -R "$SOURCE/skills/linked-records-claims" "$missing_skill_backup"
git -C "$SOURCE" rm -q -r skills/linked-records-claims
commit_all "$SOURCE" "remove one managed skill"
git -C "$SOURCE" push -q
assert_check incomplete-published-payload "$current_project" 1 \
  "local edits: none" "published  : unknown" "no complete managed payload"
assert_omits incomplete-published-payload "$RUN_OUTPUT" "published  : current"
assert_omits incomplete-published-payload "$RUN_OUTPUT" "published  : STALE"
cp -R "$missing_skill_backup" "$SOURCE/skills/linked-records-claims"
commit_all "$SOURCE" "restore managed skill"
git -C "$SOURCE" push -q

RUN_PATH="$SHIMS:$PATH" VENDOR_TEST_FORCE_PAYLOAD_READ_FAILURE=yes \
  assert_check payload-read-error "$current_project" 0 \
    "local edits: none" "published  : unknown" \
    "could not be evaluated locally"
assert_omits payload-read-error "$RUN_OUTPUT" "published  : current"
assert_omits payload-read-error "$RUN_OUTPUT" "published  : STALE"

unreachable_project="$(make_project unreachable)"
unreachable_manifest="$unreachable_project/.agents/skills/.vendored-manifest"
awk -v remote="$TEST_ROOT/missing-remote" '
  /^# vendored-from:/ { print "# vendored-from: " remote; next }
  { print }
' "$unreachable_manifest" >"$unreachable_manifest.tmp"
mv "$unreachable_manifest.tmp" "$unreachable_manifest"
assert_check unreachable "$unreachable_project" 0 \
  "local edits: none" "published  : unknown" "remote unreachable"

missing_project="$(make_project missing-payload-id)"
missing_manifest="$missing_project/.agents/skills/.vendored-manifest"
grep -v '^# payload-id:' "$missing_manifest" >"$missing_manifest.tmp"
mv "$missing_manifest.tmp" "$missing_manifest"
assert_check missing-payload-id "$missing_project" 1 \
  "local edits: none" "published  : unknown" "no payload identity"
assert_omits missing-payload-id "$RUN_OUTPUT" "published  : current"
assert_omits missing-payload-id "$RUN_OUTPUT" "published  : STALE"

no_manifest_project="$(make_project no-manifest)"
"$REAL_RM" -f -- "$no_manifest_project/.agents/skills/.vendored-manifest"
assert_check no-manifest "$no_manifest_project" 1 \
  "local edits: unknown (no manifest)" "published  : unknown (no manifest)"
assert_omits no-manifest "$RUN_OUTPUT" "invalid payload identity"

duplicate_project="$(make_project duplicate-payload-id)"
duplicate_manifest="$duplicate_project/.agents/skills/.vendored-manifest"
printf '# payload-id: %s\n' "$initial_payload" >>"$duplicate_manifest"
assert_check duplicate-payload-id "$duplicate_project" 1 \
  "local edits: none" "published  : unknown" "invalid payload identity"

malformed_project="$(make_project malformed-payload-id)"
malformed_manifest="$malformed_project/.agents/skills/.vendored-manifest"
replace_manifest_header "$malformed_manifest" '# payload-id: not-an-object-id'
assert_check malformed-payload-id "$malformed_project" 1 \
  "local edits: none" "published  : unknown" "invalid payload identity"

guard_project="$(make_project source-fidelity-guards)"
ignored_path="$SOURCE/skills/linked-records/extra.ignored"
printf '%s\n' 'ignored but copyable' >"$ignored_path"
assert_refused_without_mutation ignored-source "$guard_project" \
  "source skills differ from the committed managed payload"
"$REAL_RM" -f -- "$ignored_path"

empty_path="$SOURCE/skills/linked-records/untracked-empty"
mkdir "$empty_path"
assert_refused_without_mutation empty-directory "$guard_project" \
  "source skills differ from the committed managed payload"
rmdir "$empty_path"

hidden_path="$SOURCE/skills/linked-records/SKILL.md"
cp "$hidden_path" "$TEST_ROOT/SKILL.md.backup"
git -C "$SOURCE" update-index --assume-unchanged skills/linked-records/SKILL.md
printf '%s\n' 'hidden working-tree change' >>"$hidden_path"
assert_refused_without_mutation index-hidden "$guard_project" \
  "source skills differ from the committed managed payload"
git -C "$SOURCE" update-index --no-assume-unchanged skills/linked-records/SKILL.md
mv "$TEST_ROOT/SKILL.md.backup" "$hidden_path"

cp "$hidden_path" "$TEST_ROOT/SKILL.md.skip-backup"
git -C "$SOURCE" update-index --skip-worktree skills/linked-records/SKILL.md
printf '%s\n' 'skip-worktree-hidden change' >>"$hidden_path"
assert_refused_without_mutation skip-worktree "$guard_project" \
  "source skills differ from the committed managed payload"
git -C "$SOURCE" update-index --no-skip-worktree skills/linked-records/SKILL.md
mv "$TEST_ROOT/SKILL.md.skip-backup" "$hidden_path"

original_mode="$(mode_bits "$hidden_path")"
git -C "$SOURCE" config core.filemode false
chmod +x "$hidden_path"
[ -z "$(git -C "$SOURCE" status --porcelain -- skills/linked-records/SKILL.md)" ] ||
  fail "core.filemode=false probe was not Git-clean"
assert_refused_without_mutation filemode-masked "$guard_project" \
  "source skills differ from the committed managed payload"
chmod "$original_mode" "$hidden_path"
git -C "$SOURCE" config --unset core.filemode

git -C "$SOURCE" config filter.vendor-clean.clean \
  "sed 's/WORKTREE/COMMITTED/g'"
git -C "$SOURCE" config filter.vendor-clean.smudge cat
printf '%s\n' '*.filtered filter=vendor-clean' > \
  "$SOURCE/skills/linked-records/.gitattributes"
printf '%s\n' 'WORKTREE' >"$SOURCE/skills/linked-records/filter-probe.filtered"
commit_all "$SOURCE" "add clean-filter probe"
[ -z "$(git -C "$SOURCE" status --porcelain -- skills/)" ] ||
  fail "clean-filter probe was not Git-clean"
assert_refused_without_mutation clean-filter "$guard_project" \
  "source skills differ from the committed managed payload"
git -C "$SOURCE" rm -q skills/linked-records/.gitattributes \
  skills/linked-records/filter-probe.filtered
commit_all "$SOURCE" "remove clean-filter probe"
git -C "$SOURCE" config --unset-all filter.vendor-clean.clean
git -C "$SOURCE" config --unset-all filter.vendor-clean.smudge

nested_repo="$SOURCE/skills/linked-records/nested-link"
mkdir "$nested_repo"
git -C "$nested_repo" init -q
configure_repo "$nested_repo"
printf '%s\n' 'nested repository' >"$nested_repo/README.md"
commit_all "$nested_repo" "initial nested content"
git -C "$SOURCE" -c advice.addEmbeddedRepo=false add \
  skills/linked-records/nested-link 2>/dev/null
git -C "$SOURCE" commit -q -m "add gitlink probe"
[ -z "$(git -C "$SOURCE" status --porcelain -- skills/)" ] ||
  fail "gitlink probe was not Git-clean"
assert_refused_without_mutation committed-gitlink "$guard_project" \
  "source skills could not be compared with the committed managed payload"

git -C "$SOURCE" diff --quiet HEAD -- skills/ ||
  fail "source fixture was not restored after fidelity probes"

echo "PASS: vendor payload staleness contract"
