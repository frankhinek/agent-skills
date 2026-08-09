#!/usr/bin/env bash
# Regression matrix for the linked-records mechanical linter contract.
set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LINTER="$SCRIPT_DIR/../lint.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/linked-records-lint.XXXXXX")" || exit 2
trap 'rm -rf "$TMP_ROOT"' EXIT

put() {
  local path="$1"
  shift
  mkdir -p "${path%/*}"
  printf '%s\n' "$@" >"$path"
}

setup_no_specs() {
  mkdir -p "$1"
}

install_rm_probe() {
  local root="$1"
  put "$root/.test-bin/rm" \
    '#!/bin/sh' \
    'printf '\''%s\n'\'' "$*" >"${TMPDIR%/}/rm-called"' \
    'tmp_parent="$(CDPATH= cd -- "${TMPDIR%/}" && pwd -P)" || exit 98' \
    'case "$*" in' \
    '"-rf -- $tmp_parent/linked-records-lint.INIT00") command -p rm "$@" ;;' \
    '*) exit 99 ;;' \
    'esac'
  chmod +x "$root/.test-bin/rm"
}

setup_mktemp_failure() {
  local root="$1"
  put "$root/.test-bin/mktemp" '#!/bin/sh' 'exit 73'
  chmod +x "$root/.test-bin/mktemp"
  install_rm_probe "$root"
}

setup_mktemp_unsafe_path() {
  local root="$1"
  put "$root/.test-bin/mktemp" '#!/bin/sh' 'printf '\''/\n'\''' 'exit 0'
  chmod +x "$root/.test-bin/mktemp"
  install_rm_probe "$root"
}

setup_scratch_initialization_failure() {
  local root="$1"
  put "$root/.test-bin/mktemp" \
    '#!/bin/sh' \
    'scratch="${TMPDIR%/}/linked-records-lint.INIT00"' \
    'mkdir -p "$scratch/findings"' \
    'printf '\''%s\n'\'' "$scratch"'
  chmod +x "$root/.test-bin/mktemp"
  install_rm_probe "$root"
}

verify_case() {
  local name="$1"
  local root="$2"
  local output="$3"
  local elapsed="$4"
  case "$name" in
  mktemp-failure | mktemp-unsafe-path)
    [ ! -e "$root/rm-called" ] || return 1
    ;;
  scratch-initialization-failure)
    local canonical_root
    canonical_root="$(CDPATH= cd -- "$root" && pwd -P)" || return 1
    [ ! -e "$root/linked-records-lint.INIT00" ] || return 1
    grep -Fqx -e "-rf -- $canonical_root/linked-records-lint.INIT00" "$root/rm-called" || return 1
    ;;
  reference-scan-boundary)
    local expected
    expected="$(printf '%s\n%s' \
      './src/app.py:1: [dangling-ref] references non-existent record REQ-source-missing' \
      'linked-records lint: 1 finding(s)')"
    [ "$output" = "$expected" ] || return 1
    [ "$elapsed" -le 10 ] || return 1
    ;;
  alternate-skill-root)
    local expected
    expected="$(printf '%s\n%s\n%s' \
      './SKILL.md:6: [dangling-ref] references non-existent record GATE-root-skill-missing' \
      './src/app.py:1: [dangling-ref] references non-existent record REQ-project-missing' \
      'linked-records lint: 2 finding(s)')"
    [ "$output" = "$expected" ] || return 1
    ;;
  esac
}

setup_valid_corpus() {
  local root="$1"
  put "$root/specs/ARCH-system.md" \
    '# ARCH-system: System map' \
    '' \
    'The system is constrained by [REQ-policy](REQ-policy.md#acceptance).' \
    '' \
    '## Status' \
    '' \
    'The worker is migrating while the API remains authoritative.'
  put "$root/specs/REQ-policy.md" \
    '# REQ-policy: External policy' \
    '' \
    '## Acceptance' \
    '' \
    'Requests retain their source identifier.'
  put "$root/specs/SPEC-workflow.md" \
    '# SPEC-workflow: Distributed workflow' \
    '' \
    '## Record justification' \
    '' \
    'The behavior spans the API and worker paths, so neither is a coherent owner.' \
    '' \
    'The API publishes work that the worker consumes.'
  put "$root/specs/GATE-safety.md" \
    '# GATE-safety: Preserve safety' \
    '' \
    '## Gate' \
    '' \
    'Keep destructive operations behind explicit approval.' \
    '' \
    '## Justification' \
    '' \
    'This protects user-owned state.'
  put "$root/specs/CLAIM-atomic.md" \
    '# CLAIM-atomic: Publication is atomic' \
    '' \
    'A consumer cannot observe a partially published unit.'
  put "$root/specs/CLAIM-atomic/proof.md" 'Current proof evidence.'
  put "$root/specs/CLAIM-atomic/verification.md" 'Current verification evidence.'
}

setup_duplicate_id() {
  local root="$1"
  put "$root/a/specs/ARCH-shared.md" '# ARCH-shared: First' '' 'First map.'
  put "$root/b/specs/ARCH-shared.md" '# ARCH-shared: Second' '' 'Second map.'
}

setup_index_file() {
  put "$1/specs/README.md" '# Records' '' 'Index.'
}

setup_bad_name() {
  put "$1/specs/NOTE-invalid.md" '# NOTE-invalid: Invalid type' '' 'Invalid.'
}

setup_bad_heading() {
  put "$1/specs/ARCH-system.md" '# Wrong heading' '' 'System map.'
}

setup_broken_link() {
  put "$1/specs/ARCH-system.md" \
    '# ARCH-system: System map' '' 'See [missing detail](missing.md).'
}

setup_spec_missing_justification() {
  put "$1/specs/SPEC-flow.md" '# SPEC-flow: Flow' '' 'Distributed behavior.'
}

setup_spec_empty_justification() {
  put "$1/specs/SPEC-flow.md" \
    '# SPEC-flow: Flow' '' '## Record justification' '' '## Alternatives' '' 'None.'
}

setup_spec_duplicate_justification() {
  put "$1/specs/SPEC-flow.md" \
    '# SPEC-flow: Flow' '' \
    '## Record justification' '' 'The behavior spans the API and worker.' '' \
    '## Record justification' '' 'Neither path is a coherent owner.'
}

setup_spec_allowed_fences() {
  put "$1/specs/SPEC-flow.md" \
    '# SPEC-flow: Flow' '' \
    '## Record justification' '' \
    'The behavior spans the API and worker paths, so neither is a coherent owner.' '' \
    '```text' 'API -> worker' '```' '' \
    '~~~mermaid' 'graph LR; A --> B' '~~~' '' \
    '```plantuml' 'Alice -> Bob' '```' '' \
    '~~~dot' 'a -> b' '~~~'
}

setup_spec_unlabeled_fence() {
  put "$1/specs/SPEC-flow.md" \
    '# SPEC-flow: Flow' '' \
    '## Record justification' '' \
    'The behavior spans the API and worker paths, so neither is a coherent owner.' '' \
    '```' 'API -> worker' '```'
}

setup_spec_source_backtick() {
  put "$1/specs/SPEC-flow.md" \
    '# SPEC-flow: Flow' '' \
    '## Record justification' '' \
    'The behavior spans the API and worker paths, so neither is a coherent owner.' '' \
    '```python' 'print("source")' '```'
}

setup_spec_source_tilde() {
  put "$1/specs/SPEC-flow.md" \
    '# SPEC-flow: Flow' '' \
    '## Record justification' '' \
    'The behavior spans the API and worker paths, so neither is a coherent owner.' '' \
    '~~~bash' 'echo source' '~~~'
}

setup_gate_missing_gate() {
  put "$1/specs/GATE-safety.md" \
    '# GATE-safety: Safety' '' '## Justification' '' 'Protect state.'
}

setup_gate_missing_justification() {
  put "$1/specs/GATE-safety.md" \
    '# GATE-safety: Safety' '' '## Gate' '' 'Require approval.'
}

setup_gate_wrong_order() {
  put "$1/specs/GATE-safety.md" \
    '# GATE-safety: Safety' '' \
    '## Justification' '' 'Protect state.' '' \
    '## Gate' '' 'Require approval.'
}

setup_gate_wrong_first_h2() {
  put "$1/specs/GATE-safety.md" \
    '# GATE-safety: Safety' '' \
    '## Context' '' 'Background.' '' \
    '## Gate' '' 'Require approval.' '' \
    '## Justification' '' 'Protect state.'
}

setup_gate_status() {
  put "$1/specs/GATE-safety.md" \
    '# GATE-safety: Safety' '' \
    '## Gate' '' 'Require approval.' '' \
    '## Justification' '' 'Protect state.' '' \
    '## Status' '' 'Active.'
}

setup_claim_h2() {
  put "$1/specs/CLAIM-atomic.md" \
    '# CLAIM-atomic: Publication is atomic' '' \
    'A consumer cannot observe partial publication.' '' \
    '## Notes' '' 'Extra material.'
}

setup_claim_verdict_plain() {
  put "$1/specs/CLAIM-atomic.md" \
    '# CLAIM-atomic: Publication is atomic' '' \
    'A consumer cannot observe partial publication.' '' \
    'Verdict: pass'
}

setup_claim_proof_bold() {
  put "$1/specs/CLAIM-atomic.md" \
    '# CLAIM-atomic: Publication is atomic' '' \
    'A consumer cannot observe partial publication.' '' \
    '**Proof:** The implementation writes once.'
}

setup_claim_metadata_mixed_case() {
  put "$1/specs/CLAIM-atomic.md" \
    '# CLAIM-atomic: Publication is atomic' '' \
    'A consumer cannot observe partial publication.' '' \
    '__vErDiCt__: pass'
}

setup_tombstone_field() {
  put "$1/specs/ARCH-system.md" \
    '# ARCH-system: System map' '' 'Tombstone: replaced by the current map.'
}

setup_tombstone_status_field() {
  put "$1/specs/ARCH-system.md" \
    '# ARCH-system: System map' '' 'Status: superseded by the current map.'
}

setup_tombstone_heading() {
  put "$1/specs/ARCH-system.md" \
    '# ARCH-system: System map' '' '## Retired' '' 'Use the current map.'
}

setup_valid_gradual_status() {
  put "$1/specs/ARCH-system.md" \
    '# ARCH-system: System map' '' \
    '## Status' '' \
    'The API is authoritative while the worker migration remains incomplete.'
}

setup_orphan_evidence() {
  put "$1/specs/CLAIM-orphan/proof.md" 'Orphan proof.'
}

setup_unexpected_evidence() {
  put "$1/specs/CLAIM-atomic.md" \
    '# CLAIM-atomic: Publication is atomic' '' \
    'A consumer cannot observe partial publication.'
  put "$1/specs/CLAIM-atomic/notes.md" 'Unexpected.'
}

setup_stray_directory() {
  put "$1/specs/archive/note.md" 'Unexpected directory.'
}

setup_dangling_reference() {
  put "$1/specs/ARCH-system.md" \
    '# ARCH-system: System map' '' 'Constrained by REQ-missing.'
}

setup_reference_scan_boundary() {
  local root="$1"
  put "$root/specs/ARCH-system.md" '# ARCH-system: System map' '' 'System map.'
  put "$root/src/app.py" 'requirement = "REQ-source-missing"'
  put "$root/build/generated.js" '// REQ-build-copy'
  put "$root/dist/generated.js" '// SPEC-dist-copy'
  put "$root/.venv/lib/site-packages/package.py" '# CLAIM-dot-venv-copy'
  put "$root/venv/lib/site-packages/package.py" '# CLAIM-venv-copy'
  mkdir -p "$root/vendor/dependency"
  awk 'BEGIN {
    line = "vendored dependency content that is deliberately outside the reference scan"
    for (i = 0; i < 65536; i++) print line
    print "GATE-vendor-copy"
  }' >"$root/vendor/dependency/large.txt"
  mkfifo "$root/vendor/dependency/blocked.pipe"
  printf '\000REQ-binary-copy\n' >"$root/assets.bin"
}

setup_alternate_skill_root() {
  local root="$1"
  put "$root/specs/ARCH-system.md" '# ARCH-system: System map' '' 'System map.'
  put "$root/SKILL.md" \
    '---' \
    'name: project-skill' \
    'description: The project itself is a skill package.' \
    '---' '' \
    'Project constraint: GATE-root-skill-missing.'
  put "$root/src/app.py" 'requirement = "REQ-project-missing"'
  put "$root/.custom [client]/skill store/linked-records-claims/SKILL.md" \
    '---' \
    'name: linked-records-claims' \
    'description: Example installed skill.' \
    '---' '' \
    '```text' \
    'specs/' \
    '├── CLAIM-single-writer.md' \
    '└── CLAIM-single-writer/' \
    '```'
}

CASES='no-specs|0|linked-records lint: no specs/ directories found under @ROOT@|setup_no_specs
mktemp-failure|2|[setup] unable to create scratch directory|setup_mktemp_failure
mktemp-unsafe-path|2|[setup] unsafe scratch directory returned by mktemp: /|setup_mktemp_unsafe_path
scratch-initialization-failure|2|[setup] unable to initialize scratch directory|setup_scratch_initialization_failure
valid-corpus|0|linked-records lint: clean|setup_valid_corpus
duplicate-id|1|[unique-id] record ID in multiple specs dirs|setup_duplicate_id
index-file|1|[no-index] index-like file in specs/|setup_index_file
bad-name|1|[type] not a recognized record name|setup_bad_name
bad-heading|1|[heading] first line must be|setup_bad_heading
broken-link|1|[link] broken relative link: missing.md|setup_broken_link
spec-missing-justification|1|missing '\''## Record justification'\'' section|setup_spec_missing_justification
spec-empty-justification|1|Record justification'\'' section must contain non-empty content|setup_spec_empty_justification
spec-duplicate-justification|1|exactly one '\''## Record justification'\'' section|setup_spec_duplicate_justification
spec-allowed-fences|0|linked-records lint: clean|setup_spec_allowed_fences
spec-unlabeled-fence|1|[spec-shape] fenced block must use an approved diagram label|setup_spec_unlabeled_fence
spec-source-backtick|1|[spec-shape] fenced block must use an approved diagram label|setup_spec_source_backtick
spec-source-tilde|1|[spec-shape] fenced block must use an approved diagram label|setup_spec_source_tilde
gate-missing-gate|1|[gate-shape] missing '\''## Gate'\'' section|setup_gate_missing_gate
gate-missing-justification|1|[gate-shape] missing '\''## Justification'\'' section|setup_gate_missing_justification
gate-wrong-order|1|'\''## Gate'\'' must precede '\''## Justification'\''|setup_gate_wrong_order
gate-wrong-first-h2|1|substantive content must start with '\''## Gate'\''|setup_gate_wrong_first_h2
gate-status|1|'\''## Status'\'' is not allowed on GATE records|setup_gate_status
claim-h2|1|[claim-shape] CLAIM records hold only the property statement|setup_claim_h2
claim-verdict-plain|1|claim-level proof/verdict material belongs in|setup_claim_verdict_plain
claim-proof-bold|1|claim-level proof/verdict material belongs in|setup_claim_proof_bold
claim-metadata-mixed-case|1|claim-level proof/verdict material belongs in|setup_claim_metadata_mixed_case
tombstone-field|1|[tombstone] explicit tombstone marker|setup_tombstone_field
tombstone-status-field|1|[tombstone] explicit tombstone marker|setup_tombstone_status_field
tombstone-heading|1|[tombstone] explicit tombstone marker|setup_tombstone_heading
valid-gradual-status|0|linked-records lint: clean|setup_valid_gradual_status
orphan-evidence|1|[orphan-evidence] evidence directory without a CLAIM-orphan.md record|setup_orphan_evidence
unexpected-evidence|1|[evidence-shape] unexpected evidence file|setup_unexpected_evidence
stray-directory|1|[stray-dir] unexpected directory in specs/|setup_stray_directory
dangling-reference|1|[dangling-ref] references non-existent record REQ-missing|setup_dangling_reference
reference-scan-boundary|1|[dangling-ref] references non-existent record REQ-source-missing|setup_reference_scan_boundary
alternate-skill-root|1|[dangling-ref] references non-existent record REQ-project-missing|setup_alternate_skill_root'

declared="$(printf '%s\n' "$CASES" | awk 'NF { count++ } END { print count + 0 }')"
executed=0
failed=0

if [ "$declared" -eq 0 ]; then
  printf 'FAIL matrix: no cases declared\n'
  failed=$((failed + 1))
fi

while IFS='|' read -r name expected_rc expected_text setup; do
  [ -n "$name" ] || continue
  root="$TMP_ROOT/$name"
  "$setup" "$root"

  fifo_writer=""
  if [ "$name" = reference-scan-boundary ]; then
    (printf '%s\n' 'REQ-fifo-copy' >"$root/vendor/dependency/blocked.pipe") &
    fifo_writer=$!
  fi

  started="$(date +%s)"
  if [ -d "$root/.test-bin" ]; then
    output="$(TMPDIR="$root" PATH="$root/.test-bin:$PATH" "$LINTER" "$root" 2>&1)"
  else
    output="$("$LINTER" "$root" 2>&1)"
  fi
  rc=$?
  elapsed=$(( $(date +%s) - started ))
  if [ -n "$fifo_writer" ]; then
    kill "$fifo_writer" 2>/dev/null || true
    wait "$fifo_writer" 2>/dev/null || true
  fi
  executed=$((executed + 1))
  canonical_root="$(CDPATH= cd -- "$root" && pwd -P)"
  expected_text="${expected_text//@ROOT@/$canonical_root}"

  if [ "$rc" -ne "$expected_rc" ]; then
    printf 'FAIL %s: expected exit %s, got %s\n%s\n' "$name" "$expected_rc" "$rc" "$output"
    failed=$((failed + 1))
    continue
  fi
  if ! printf '%s\n' "$output" | grep -Fq "$expected_text"; then
    printf 'FAIL %s: missing expected output: %s\n%s\n' "$name" "$expected_text" "$output"
    failed=$((failed + 1))
    continue
  fi
  if ! verify_case "$name" "$root" "$output" "$elapsed"; then
    printf 'FAIL %s: case-specific verification failed (%ss)\n%s\n' "$name" "$elapsed" "$output"
    failed=$((failed + 1))
    continue
  fi
  printf 'PASS %s\n' "$name"
done <<EOF
$CASES
EOF

if [ "$executed" -ne "$declared" ]; then
  printf 'FAIL matrix: declared %s cases, executed %s\n' "$declared" "$executed"
  failed=$((failed + 1))
fi

if [ "$failed" -ne 0 ]; then
  printf 'lint regression matrix: %s failure(s), %s/%s cases executed\n' "$failed" "$executed" "$declared"
  exit 1
fi

printf 'lint regression matrix: clean (%s cases)\n' "$executed"
