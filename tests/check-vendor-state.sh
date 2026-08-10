#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO/vendor.sh"
REAL_RM="$(type -P rm)"
REAL_AWK="$(type -P awk)"
ORIGINAL_PATH="$PATH"
TEST_PARENT="${TMPDIR:-/tmp}"
TEST_ROOT="$(mktemp -d "$TEST_PARENT/linked-records-vendor-state.XXXXXX")"
PROJECTS="$TEST_ROOT/projects"
SNAPSHOTS="$TEST_ROOT/snapshots"
SPY_BIN="$TEST_ROOT/git-spy-bin"
COMPARISON_SPY_BIN="$TEST_ROOT/comparison-spy-bin"
GIT_SPY_LOG="$TEST_ROOT/git-calls"
SKILLS=(linked-records linked-records-claims linked-records-upkeep)

unset BASH_ENV ENV
unset -f rm 2>/dev/null || true
unset -f git 2>/dev/null || true
unset -f awk 2>/dev/null || true

cleanup() {
  case "$TEST_ROOT" in
  "$TEST_PARENT/linked-records-vendor-state."*) "$REAL_RM" -rf -- "$TEST_ROOT" ;;
  *) echo "refusing to clean unexpected test root: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

snapshot_tree() {
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

assert_equals() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  [ "$actual" = "$expected" ] ||
    fail "$name differed; expected '$expected', got '$actual'"
}

run_vendor() {
  set +e
  RUN_OUTPUT="$("$VENDOR" "$@" 2>&1)"
  RUN_STATUS=$?
  set -e
}

run_vendor_split() {
  local name="$1"
  local command_path="$2"
  shift 2
  local stdout_file="$TEST_ROOT/$name.stdout"
  local stderr_file="$TEST_ROOT/$name.stderr"

  set +e
  PATH="$command_path" "$VENDOR" "$@" >"$stdout_file" 2>"$stderr_file"
  RUN_STATUS=$?
  set -e
  RUN_STDOUT="$(<"$stdout_file")"
  RUN_STDERR="$(<"$stderr_file")"
}

run_structural_check() {
  local root="$1"
  local no_positional="$2"
  set +e
  if [ "$no_positional" = yes ]; then
    RUN_OUTPUT="$(cd "$root" && PATH="$SPY_BIN:$ORIGINAL_PATH" GIT_SPY_LOG="$GIT_SPY_LOG" "$VENDOR" --check 2>&1)"
  else
    RUN_OUTPUT="$(PATH="$SPY_BIN:$ORIGINAL_PATH" GIT_SPY_LOG="$GIT_SPY_LOG" "$VENDOR" --check "$root" 2>&1)"
  fi
  RUN_STATUS=$?
  set -e
}

make_copy_project() {
  local name="$1"
  local root="$PROJECTS/$name"
  mkdir -p "$root"
  "$VENDOR" --copy "$root" >/dev/null
  printf '%s\n' "$root"
}

make_link_project() {
  local name="$1"
  local root="$PROJECTS/$name"
  mkdir -p "$root"
  "$VENDOR" --link "$root" >/dev/null
  printf '%s\n' "$root"
}

replace_with_exact_link() {
  local root="$1"
  local skill="$2"
  "$REAL_RM" -rf -- "$root/.agents/skills/$skill"
  ln -s "$REPO/skills/$skill" "$root/.agents/skills/$skill"
}

assert_read_only_result() {
  local name="$1"
  local root="$2"
  local expected_status="$3"
  shift 3
  snapshot_tree "$root" "$SNAPSHOTS/$name.before"
  run_vendor "$@"
  [ "$RUN_STATUS" -eq "$expected_status" ] ||
    fail "$name returned $RUN_STATUS instead of $expected_status: $RUN_OUTPUT"
  snapshot_tree "$root" "$SNAPSHOTS/$name.after"
  cmp -s "$SNAPSHOTS/$name.before" "$SNAPSHOTS/$name.after" ||
    fail "$name changed the project tree"
}

assert_structural_failure() {
  local name="$1"
  local root="$2"
  local state_core="$3"
  local state_claims="$4"
  local state_upkeep="$5"
  local no_positional="${6:-no}"

  : >"$GIT_SPY_LOG"
  snapshot_tree "$root" "$SNAPSHOTS/$name.before"
  run_structural_check "$root" "$no_positional"
  [ "$RUN_STATUS" -eq 1 ] ||
    fail "$name returned $RUN_STATUS instead of 1: $RUN_OUTPUT"

  assert_contains "$name" "$RUN_OUTPUT" "  linked-records: $state_core"
  assert_contains "$name" "$RUN_OUTPUT" "  linked-records-claims: $state_claims"
  assert_contains "$name" "$RUN_OUTPUT" "  linked-records-upkeep: $state_upkeep"
  assert_contains "$name" "$RUN_OUTPUT" \
    "Preserve or move only affected linked-records entries under .agents/skills before recovery."
  assert_contains "$name" "$RUN_OUTPUT" "Inspect and merge any local work"
  assert_contains "$name" "$RUN_OUTPUT" "--copy"
  assert_contains "$name" "$RUN_OUTPUT" "--link"
  assert_omits "$name" "$RUN_OUTPUT" "--force"
  assert_omits "$name" "$RUN_OUTPUT" "provenance"
  assert_omits "$name" "$RUN_OUTPUT" "local edits"
  assert_omits "$name" "$RUN_OUTPUT" "published"

  snapshot_tree "$root" "$SNAPSHOTS/$name.after"
  cmp -s "$SNAPSHOTS/$name.before" "$SNAPSHOTS/$name.after" ||
    fail "$name changed the project tree"
  [ ! -s "$GIT_SPY_LOG" ] ||
    fail "$name called git before rejecting structural state: $(sed -n '1,20p' "$GIT_SPY_LOG")"
}

mkdir -p "$PROJECTS" "$SNAPSHOTS" "$SPY_BIN" "$COMPARISON_SPY_BIN"

linked_project="$(make_link_project all-linked)"

copied_project="$(make_copy_project all-copied)"
copied_manifest="$copied_project/.agents/skills/.vendored-manifest"
{
  printf '# vendored-from: %s\n' "$TEST_ROOT/unreachable-remote"
  grep -v '^# vendored-from:' "$copied_manifest"
} >"$copied_manifest.tmp"
mv "$copied_manifest.tmp" "$copied_manifest"

edited_project="$(make_copy_project edited-diagnostics)"
edited_manifest="$edited_project/.agents/skills/.vendored-manifest"
{
  printf '# vendored-from: %s\n' "$TEST_ROOT/unreachable-remote"
  grep -v '^# vendored-from:' "$edited_manifest"
} >"$edited_manifest.tmp"
mv "$edited_manifest.tmp" "$edited_manifest"
printf '\nlocal claims edit\n' >>"$edited_project/.agents/skills/linked-records-claims/SKILL.md"
printf '\nlocal core edit\n' >>"$edited_project/.agents/skills/linked-records/SKILL.md"

missing_manifest_project="$(make_copy_project copied-no-manifest)"
"$REAL_RM" -f -- "$missing_manifest_project/.agents/skills/.vendored-manifest"

empty_copied_project="$(make_copy_project copied-empty-shells)"
for skill in "${SKILLS[@]}"; do
  find "$empty_copied_project/.agents/skills/$skill" -type f \
    -exec "$REAL_RM" -f -- {} \;
done

fresh_project="$PROJECTS/fresh-wrong-directory"
mkdir -p "$fresh_project"

foreign_skills_project="$PROJECTS/foreign-skills-only"
mkdir -p "$foreign_skills_project/.agents/skills/other-skill"
printf '%s\n' 'unrelated skill' >"$foreign_skills_project/.agents/skills/other-skill/SKILL.md"

all_missing_project="$(make_copy_project all-missing-retained-manifest)"
for skill in "${SKILLS[@]}"; do
  "$REAL_RM" -rf -- "$all_missing_project/.agents/skills/$skill"
done

all_missing_link_project="$(make_link_project all-missing-linked-install)"
for skill in "${SKILLS[@]}"; do
  "$REAL_RM" -rf -- "$all_missing_link_project/.agents/skills/$skill"
done

for skill in "${SKILLS[@]}"; do
  copied_missing="$(make_copy_project "copied-missing-$skill")"
  "$REAL_RM" -rf -- "$copied_missing/.agents/skills/$skill"

  linked_missing="$(make_link_project "linked-missing-$skill")"
  "$REAL_RM" -rf -- "$linked_missing/.agents/skills/$skill"
done

first_linked_project="$(make_copy_project mixed-first-linked)"
replace_with_exact_link "$first_linked_project" linked-records

first_copied_project="$(make_copy_project mixed-first-copied)"
replace_with_exact_link "$first_copied_project" linked-records-claims
replace_with_exact_link "$first_copied_project" linked-records-upkeep

regular_file_project="$(make_copy_project invalid-regular-file)"
"$REAL_RM" -rf -- "$regular_file_project/.agents/skills/linked-records-claims"
printf '%s\n' 'not a skill directory' >"$regular_file_project/.agents/skills/linked-records-claims"

dangling_link_project="$(make_link_project invalid-dangling-link)"
"$REAL_RM" -f -- "$dangling_link_project/.agents/skills/linked-records-claims"
ln -s "$TEST_ROOT/absent-skill" "$dangling_link_project/.agents/skills/linked-records-claims"

wrong_target_project="$(make_link_project invalid-wrong-target-link)"
mkdir -p "$wrong_target_project/wrong-target"
"$REAL_RM" -f -- "$wrong_target_project/.agents/skills/linked-records-upkeep"
ln -s "$wrong_target_project/wrong-target" "$wrong_target_project/.agents/skills/linked-records-upkeep"

# Create the recording shim before any checked process receives the spy PATH.
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'printf '\''git %s\n'\'' "$*" >>"$GIT_SPY_LOG"'
  printf '%s\n' 'exit 97'
} >"$SPY_BIN/git"
chmod +x "$SPY_BIN/git"

{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'if [ "$#" -eq 3 ] && [ -r "$2" ] && [ -r "$3" ]; then'
  printf '%s\n' "    printf '%s\\n' '.agents/skills/fake-partial-path'"
  printf '%s\n' "    printf '%s\\n' '.agents/skills/fake-partial-path' >&2"
  printf '%s\n' '    exit 2'
  printf '%s\n' 'fi'
  printf 'exec %q "$@"\n' "$REAL_AWK"
} >"$COMPARISON_SPY_BIN/awk"
chmod +x "$COMPARISON_SPY_BIN/awk"

# Prove the PATH spy observes vendor.sh's only network-capable command before
# empty logs are accepted as evidence in structural-failure cases.
run_structural_check "$copied_project" no
[ "$RUN_STATUS" -eq 0 ] ||
  fail "git spy positive control returned $RUN_STATUS: $RUN_OUTPUT"
grep -Fq -- "git ls-remote" "$GIT_SPY_LOG" ||
  fail "git spy positive control did not observe vendor.sh"
: >"$GIT_SPY_LOG"

assert_read_only_result all-linked "$linked_project" 0 --check "$linked_project"
assert_contains all-linked "$RUN_OUTPUT" "skills are symlinked (link mode)"

assert_read_only_result all-copied "$copied_project" 0 --check "$copied_project"
assert_contains all-copied "$RUN_OUTPUT" "provenance :"
assert_contains all-copied "$RUN_OUTPUT" "local edits: none"
assert_contains all-copied "$RUN_OUTPUT" "published  : unknown (remote unreachable)"

expected_edit_paths="$(printf '  content changed: %s\n' \
  '.agents/skills/linked-records-claims/SKILL.md' \
  '.agents/skills/linked-records/SKILL.md')"

snapshot_tree "$edited_project" "$SNAPSHOTS/edited-check.before"
run_vendor_split edited-check "$ORIGINAL_PATH" --check "$edited_project"
[ "$RUN_STATUS" -eq 1 ] ||
  fail "edited check returned $RUN_STATUS instead of 1: $RUN_STDOUT $RUN_STDERR"
assert_contains edited-check "$RUN_STDOUT" "provenance :"
assert_contains edited-check "$RUN_STDOUT" "local edits: YES"
assert_contains edited-check "$RUN_STDOUT" "published  : unknown (remote unreachable)"
assert_equals edited-check-stderr "$RUN_STDERR" ""
check_edit_paths="$(printf '%s\n' "$RUN_STDOUT" | awk '
  /^local edits: YES/ { capture = 1; next }
  /^published  :/ { capture = 0 }
  capture
')"
assert_equals edited-check-paths "$check_edit_paths" "$expected_edit_paths"
snapshot_tree "$edited_project" "$SNAPSHOTS/edited-check.after"
cmp -s "$SNAPSHOTS/edited-check.before" "$SNAPSHOTS/edited-check.after" ||
  fail "edited check changed the project tree"

snapshot_tree "$edited_project" "$SNAPSHOTS/edited-refresh.before"
run_vendor_split edited-refresh "$ORIGINAL_PATH" --copy "$edited_project"
[ "$RUN_STATUS" -eq 1 ] ||
  fail "edited refresh returned $RUN_STATUS instead of 1: $RUN_STDOUT $RUN_STDERR"
assert_equals edited-refresh-stdout "$RUN_STDOUT" ""
assert_contains edited-refresh "$RUN_STDERR" "error: vendored skills were edited since they were vendored:"
assert_contains edited-refresh "$RUN_STDERR" "Merge those edits into the canonical repo, or re-run with --force"
assert_contains edited-refresh "$RUN_STDERR" "to discard them."
refresh_edit_paths="$(printf '%s\n' "$RUN_STDERR" | awk '
  /^error: vendored skills were edited/ { capture = 1; next }
  /^Merge those edits/ { capture = 0 }
  capture
')"
assert_equals edited-refresh-paths "$refresh_edit_paths" "$expected_edit_paths"
snapshot_tree "$edited_project" "$SNAPSHOTS/edited-refresh.after"
cmp -s "$SNAPSHOTS/edited-refresh.before" "$SNAPSHOTS/edited-refresh.after" ||
  fail "edited refresh changed the project tree"

for mode in check refresh; do
  snapshot_tree "$edited_project" "$SNAPSHOTS/comparison-error-$mode.before"
  if [ "$mode" = check ]; then
    run_vendor_split comparison-error-check "$COMPARISON_SPY_BIN:$ORIGINAL_PATH" --check "$edited_project"
  else
    run_vendor_split comparison-error-refresh "$COMPARISON_SPY_BIN:$ORIGINAL_PATH" --copy "$edited_project"
  fi
  [ "$RUN_STATUS" -eq 2 ] ||
    fail "comparison-error $mode returned $RUN_STATUS instead of 2: $RUN_STDOUT $RUN_STDERR"
  assert_contains "comparison-error $mode" "$RUN_STDERR" "error: inventory comparison failed (status 2)"
  assert_omits "comparison-error $mode stdout" "$RUN_STDOUT" ".agents/skills/fake-partial-path"
  assert_omits "comparison-error $mode stderr" "$RUN_STDERR" ".agents/skills/fake-partial-path"
  snapshot_tree "$edited_project" "$SNAPSHOTS/comparison-error-$mode.after"
  cmp -s "$SNAPSHOTS/comparison-error-$mode.before" "$SNAPSHOTS/comparison-error-$mode.after" ||
    fail "comparison-error $mode changed the project tree"
done

# A coherent copied tree stays in the manifest pipeline, including its
# existing missing-manifest status and output semantics.
assert_read_only_result copied-no-manifest "$missing_manifest_project" 1 --check "$missing_manifest_project"
assert_omits copied-no-manifest "$RUN_OUTPUT" "incoherent vendoring state"
assert_omits copied-no-manifest "$RUN_OUTPUT" "skill states:"

assert_structural_failure copied-empty-shells "$empty_copied_project" invalid invalid invalid
assert_contains copied-empty-shells "$RUN_OUTPUT" "incoherent linked-records vendoring state"

assert_structural_failure fresh-wrong-directory "$fresh_project" missing missing missing yes
assert_contains fresh-wrong-directory "$RUN_OUTPUT" "not installed here"
assert_contains fresh-wrong-directory "$RUN_OUTPUT" "wrong project directory"

assert_structural_failure foreign-skills-only "$foreign_skills_project" missing missing missing
assert_contains foreign-skills-only "$RUN_OUTPUT" "not installed here"
assert_contains foreign-skills-only "$RUN_OUTPUT" "wrong project directory"
assert_omits foreign-skills-only "$RUN_OUTPUT" "incoherent linked-records vendoring state"

assert_structural_failure all-missing-retained-manifest "$all_missing_project" missing missing missing
assert_contains all-missing-retained-manifest "$RUN_OUTPUT" "incoherent linked-records vendoring state"
assert_omits all-missing-retained-manifest "$RUN_OUTPUT" "not installed here"
assert_omits all-missing-retained-manifest "$RUN_OUTPUT" "wrong project directory"

assert_structural_failure all-missing-linked-install "$all_missing_link_project" missing missing missing
assert_contains all-missing-linked-install "$RUN_OUTPUT" "not installed here"
assert_contains all-missing-linked-install "$RUN_OUTPUT" "wrong project directory"
assert_omits all-missing-linked-install "$RUN_OUTPUT" "incoherent linked-records vendoring state"

assert_structural_failure copied-missing-core \
  "$PROJECTS/copied-missing-linked-records" missing copied copied
assert_structural_failure copied-missing-claims \
  "$PROJECTS/copied-missing-linked-records-claims" copied missing copied
assert_structural_failure copied-missing-upkeep \
  "$PROJECTS/copied-missing-linked-records-upkeep" copied copied missing

assert_structural_failure linked-missing-core \
  "$PROJECTS/linked-missing-linked-records" missing linked linked
assert_structural_failure linked-missing-claims \
  "$PROJECTS/linked-missing-linked-records-claims" linked missing linked
assert_structural_failure linked-missing-upkeep \
  "$PROJECTS/linked-missing-linked-records-upkeep" linked linked missing

assert_structural_failure mixed-first-linked "$first_linked_project" linked copied copied
assert_structural_failure mixed-first-copied "$first_copied_project" copied linked linked
assert_structural_failure invalid-regular-file "$regular_file_project" copied invalid copied
assert_structural_failure invalid-dangling-link "$dangling_link_project" linked invalid linked
assert_structural_failure invalid-wrong-target-link "$wrong_target_project" linked linked invalid

echo "PASS: vendor state contract"
