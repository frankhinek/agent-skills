#!/usr/bin/env bash
# Run the linked-records behavioral evals against a harness.
#
# Usage: run.sh <claude|codex> [scenario ...]     (default: all scenarios)
#
# Each scenario: build a fresh fixture, apply the scenario overlay if any,
# run the harness headlessly with the scenario prompt, then run check.sh
# (mechanical postconditions) inside the fixture. Final responses and
# diagnostic logs and final repository diffs go to a fresh
# results/<date>-<harness>-<run-id>/ directory. Logs are gitignored; the
# summary and diffs may be committed as durable run evidence.
set -uo pipefail

EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX="$EVALS/harness-sandbox.sh"
source "$EVALS/run-fixture-lifecycle.sh"
HARNESS="${1:?usage: run.sh <claude|codex> [scenario ...]}"
shift || true

EVAL_FIXTURE_RETENTION="${EVAL_FIXTURE_RETENTION:-never}"
case "$EVAL_FIXTURE_RETENTION" in
never|failed|always) ;;
*)
  echo "EVAL_FIXTURE_RETENTION must be never, failed, or always" >&2
  exit 2
  ;;
esac

case "$HARNESS" in
claude)
  HARNESS_NAME="Claude"
  HARNESS_BIN="$(type -P claude 2>/dev/null || true)"
  ;;
codex)
  HARNESS_NAME="Codex"
  HARNESS_BIN="$(type -P codex 2>/dev/null || true)"
  ;;
*)
  echo "unsupported harness: $HARNESS" >&2
  exit 2
  ;;
esac

AVAILABLE_SCENARIOS=()
for d in "$EVALS/scenarios"/[!.]*/; do
  [ -d "$d" ] || continue
  d="${d%/}"
  AVAILABLE_SCENARIOS+=("${d##*/}")
done

SCENARIOS=()
UNKNOWN_SCENARIOS=()
if [ $# -gt 0 ]; then
  for requested in "$@"; do
    known=0
    if [ "${#AVAILABLE_SCENARIOS[@]}" -gt 0 ]; then
      for available in "${AVAILABLE_SCENARIOS[@]}"; do
        if [ "$requested" = "$available" ]; then
          known=1
          break
        fi
      done
    fi
    if [ "$known" -eq 1 ]; then
      SCENARIOS+=("$requested")
    else
      UNKNOWN_SCENARIOS+=("$requested")
    fi
  done
elif [ "${#AVAILABLE_SCENARIOS[@]}" -gt 0 ]; then
  SCENARIOS=("${AVAILABLE_SCENARIOS[@]}")
fi

DATE="$(date +%Y-%m-%d)"
if [ -n "${EVAL_LABEL:-}" ]; then
  case "$EVAL_LABEL" in
  [A-Za-z0-9]*)
    case "$EVAL_LABEL" in
    *[!A-Za-z0-9._-]*)
      echo "invalid EVAL_LABEL: use only ASCII letters, digits, dots, underscores, and hyphens" >&2
      exit 2
      ;;
    esac
    ;;
  *)
    echo "invalid EVAL_LABEL: start with an ASCII letter or digit" >&2
    exit 2
    ;;
  esac
  RUN_ID="$EVAL_LABEL"
else
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
fi
OUT="$EVALS/results/$DATE-$HARNESS-$RUN_ID"
summary="$OUT/summary.md"

if ! mkdir -p -- "$EVALS/results"; then
  echo "result parent directory could not be created: $EVALS/results" >&2
  exit 2
fi
if ! mkdir -- "$OUT" 2>/dev/null; then
  if [ -e "$OUT" ] || [ -L "$OUT" ]; then
    echo "result directory already exists: $OUT" >&2
  else
    echo "result directory could not be created: $OUT" >&2
  fi
  exit 2
fi

summary_write_failed() {
  echo "result summary write failed: $summary" >&2
  exit 1
}

write_summary_header() {
  if printf '%s\n' \
    '---' \
    "summary: \"Records the $HARNESS_NAME linked-records behavioral eval run from $DATE.\"" \
    'read_when:' \
    '  - Comparing linked-records behavior across harnesses or model versions' \
    "  - Investigating this eval run's mechanical and escalation results" \
    "title: \"$HARNESS_NAME Eval Run — $DATE\"" \
    '---' \
    >"$summary"; then
    :
  else
    summary_write_failed
  fi
}

if [ "${#UNKNOWN_SCENARIOS[@]}" -gt 0 ] || [ "${#SCENARIOS[@]}" -eq 0 ]; then
  write_summary_header
  if {
    echo
    echo "# Eval run: $HARNESS, $DATE"
    echo
    echo "- status: INVALID: scenario selection"
    echo "- scenarios executed: 0"
    if [ "${#UNKNOWN_SCENARIOS[@]}" -gt 0 ]; then
      echo "- detail: requested set rejected before execution; valid selections, if any, were not run"
      echo "- unknown scenarios:"
      for unknown in "${UNKNOWN_SCENARIOS[@]}"; do
        if [ -n "$unknown" ]; then
          printf '  - %q\n' "$unknown"
        else
          echo "  - <empty>"
        fi
      done
    else
      echo "- detail: no scenarios discovered"
    fi
  } >>"$summary"; then
    :
  else
    summary_write_failed
  fi

  if [ "${#UNKNOWN_SCENARIOS[@]}" -gt 0 ]; then
    for unknown in "${UNKNOWN_SCENARIOS[@]}"; do
      if [ -n "$unknown" ]; then
        printf 'unknown scenario: %q\n' "$unknown" >&2
      else
        echo "unknown scenario: <empty>" >&2
      fi
    done
  fi
  [ "${#SCENARIOS[@]}" -gt 0 ] || echo "no scenarios selected" >&2
  echo "summary: $summary"
  exit 2
fi

if ! mkdir -- "$OUT/logs" "$OUT/diffs"; then
  echo "result artifact directories could not be created under: $OUT" >&2
  exit 2
fi
write_summary_header

if ! safety_profile="$("$SANDBOX" --profile-id 2>/dev/null)" || [ -z "$safety_profile" ]; then
  safety_profile="unavailable"
fi
if ! sandbox_version="$("$SANDBOX" --backend-version 2>/dev/null)" || [ -z "$sandbox_version" ]; then
  sandbox_version="unavailable"
fi

if {
  echo
  echo "# Eval run: $HARNESS, $DATE"
  echo
  if [ -n "$HARNESS_BIN" ]; then
    version="$("$HARNESS_BIN" --version 2>/dev/null | head -1)"
  else
    version=""
  fi
  echo "- version: ${version:-unavailable}"
  [ -z "${EVAL_CLAUDE_ARGS:-}${EVAL_CODEX_ARGS:-}" ] ||
    echo "- pinned args: ${EVAL_CLAUDE_ARGS:-}${EVAL_CODEX_ARGS:-}"
  echo "- safety profile: $safety_profile"
  echo "- sandbox backend: $sandbox_version"
  echo "- writable project tree: scenario fixture only (.git read-only; .agents writable)"
  echo "- network: enabled for harness and child processes"
  echo "- harness permissions: inner checks bypassed; outer sandbox authoritative"
  case "$HARNESS" in
  claude)
    echo "- harness startup: fixture-local writable config; host secure-storage authentication; project settings only; MCP, Chrome, and session persistence disabled"
    ;;
  codex)
    echo "- harness startup: fixture-local CODEX_HOME; user config, rules, plugins, apps, and multi-agent disabled; ephemeral session"
    ;;
  esac
  echo "- safety checks: .agents write and .git/sibling denial before subject; sibling escape canaries after subject and postconditions"
  echo "- final responses and diagnostics: logs/"
  echo "- final repository diffs: diffs/"
  echo "- mechanical checks below; judge escalation quality from final responses"
} >>"$summary"; then
  :
else
  summary_write_failed
fi

record_invalid() {
  local scenario="$1"
  local reason="$2"
  local detail="$3"
  local duration="$4"
  if {
    echo
    echo "## $scenario"
    echo
    echo "- status: INVALID: $reason"
    echo "- detail: $detail"
    echo "- duration: ${duration}s"
    echo "- diagnostics: logs/$scenario.log"
    if [ -f "$OUT/diffs/$scenario.patch" ]; then
      echo "- repository diff: diffs/$scenario.patch"
    fi
  } >>"$summary"; then
    :
  else
    summary_write_failed
  fi
  echo "INVALID: $reason — $detail"
  echo
}

remove_probe_artifact() {
  local path="$1"

  if [ -d "$path" ] && [ ! -L "$path" ]; then
    rmdir -- "$path"
  else
    rm -f -- "$path"
  fi
}

capture_repository_diff() {
  local fixture="$1"
  local baseline="$2"
  local output="$3"
  local diagnostic_log="$4"
  local scratch_dir="$5"
  local untracked_list file_patch path diff_rc capture_rc append_rc

  untracked_list="$(mktemp "$scratch_dir/final-untracked.XXXXXX")" || return 73
  file_patch="$(mktemp "$scratch_dir/final-file-patch.XXXXXX")" || {
    rm -f -- "$untracked_list"
    return 73
  }

  git -C "$fixture" --no-pager diff --no-ext-diff --binary --full-index \
    "$baseline" -- >"$output" 2>>"$diagnostic_log"
  capture_rc=$?
  if [ "$capture_rc" -eq 0 ]; then
    git -C "$fixture" ls-files --others --exclude-standard -z \
      >"$untracked_list" 2>>"$diagnostic_log"
    capture_rc=$?
  fi

  while [ "$capture_rc" -eq 0 ] && IFS= read -r -d '' path; do
    case "$path" in
    .eval-runtime | .eval-runtime/*) continue ;;
    esac
    : >"$file_patch" || {
      capture_rc=74
      break
    }
    git -C "$fixture" --no-pager diff --no-index --no-ext-diff --binary \
      --full-index -- /dev/null "$path" >"$file_patch" 2>>"$diagnostic_log"
    diff_rc=$?
    case "$diff_rc" in
    0)
      if [ -s "$file_patch" ]; then
        capture_rc=74
      fi
      ;;
    1)
      if [ ! -s "$file_patch" ]; then
        capture_rc=74
      else
        cat "$file_patch" >>"$output"
        append_rc=$?
        [ "$append_rc" -eq 0 ] || capture_rc="$append_rc"
      fi
      ;;
    *) capture_rc="$diff_rc" ;;
    esac
  done <"$untracked_list"

  rm -f -- "$untracked_list" "$file_patch"
  return "$capture_rc"
}

scan_changed_files_for_auth_material() {
  local fixture="$1"
  local baseline="$2"
  local auth_file="$3"
  local scratch_dir="$4"
  local diagnostic_log="$5"
  local patch_file="$6"
  local patterns candidates path scan_rc result

  patterns="$(mktemp "$scratch_dir/auth-patterns.XXXXXX")" || return 77
  candidates="$(mktemp "$scratch_dir/auth-candidates.XXXXXX")" || {
    rm -f -- "$patterns"
    return 77
  }

  LC_ALL=C awk '
    function emit() {
      if (length(token) >= 16) print token
      token = ""
    }
    {
      for (i = 1; i <= length($0); i++) {
        char = substr($0, i, 1)
        if (char ~ /[[:alnum:]_.=-]/) token = token char
        else emit()
      }
      emit()
    }
  ' "$auth_file" >"$patterns" 2>>"$diagnostic_log"
  result=$?
  if [ "$result" -eq 0 ]; then
    sort -u "$patterns" -o "$patterns" 2>>"$diagnostic_log"
    result=$?
  fi
  if [ "$result" -eq 0 ] && [ -s "$patterns" ]; then
    git -C "$fixture" diff --name-only -z "$baseline" -- \
      >"$candidates" 2>>"$diagnostic_log"
    result=$?
    if [ "$result" -eq 0 ]; then
      git -C "$fixture" ls-files --others --exclude-standard -z \
        >>"$candidates" 2>>"$diagnostic_log"
      result=$?
    fi
  fi

  while [ "$result" -eq 0 ] && [ -s "$patterns" ] &&
    IFS= read -r -d '' path; do
    case "$path" in
    .eval-runtime | .eval-runtime/*) continue ;;
    esac
    if [ -f "$fixture/$path" ] && [ ! -L "$fixture/$path" ]; then
      grep -F -f "$patterns" -- "$fixture/$path" >/dev/null 2>>"$diagnostic_log"
      scan_rc=$?
      case "$scan_rc" in
      0) result=76 ;;
      1) ;;
      *) result=77 ;;
      esac
    fi
  done <"$candidates"

  if [ "$result" -eq 0 ] && [ -s "$patterns" ]; then
    grep -F -f "$patterns" -- "$patch_file" >/dev/null 2>>"$diagnostic_log"
    scan_rc=$?
    case "$scan_rc" in
    0) result=76 ;;
    1) ;;
    *) result=77 ;;
    esac
  fi

  rm -f -- "$patterns" "$candidates"
  return "$result"
}

overall=0
eval_fixture_temp_init
fixture_temp_rc=$?
if [ "$fixture_temp_rc" -ne 0 ]; then
  for s in "${SCENARIOS[@]}"; do
    : >"$OUT/logs/$s.log"
    record_invalid "$s" "setup" \
      "temporary fixture root creation or validation failed (exit $fixture_temp_rc)" 0
  done
  echo "summary: $summary"
  exit 1
fi

scenario_number=0
for s in "${SCENARIOS[@]}"; do
  sd="$EVALS/scenarios/$s"

  log="$OUT/logs/$s.log"
  response="$OUT/logs/$s.response.txt"
  repository_diff="$OUT/diffs/$s.patch"
  : >"$log"
  : >"$response"
  rm -f -- "$repository_diff"
  echo "== $s ($HARNESS) =="
  start="$(date +%s)"

  scenario_number=$((scenario_number + 1))
  fixture_parent="$EVAL_FIXTURE_ROOT/$scenario_number-$s"
  if ! mkdir -- "$fixture_parent"; then
    overall=1
    record_invalid "$s" "setup" "temporary fixture directory creation failed" 0
    continue
  fi
  fx="$fixture_parent/fixture"

  "$EVALS/fixture.sh" "$fx" >>"$log" 2>&1
  setup_rc=$?
  if [ "$setup_rc" -eq 0 ] && [ -d "$sd/overlay" ]; then
    (cp -R "$sd/overlay/." "$fx/" &&
      git -C "$fx" add -A &&
      git -C "$fx" commit -qm "overlay") >>"$log" 2>&1
    setup_rc=$?
  fi
  if [ "$setup_rc" -ne 0 ]; then
    dur=$(($(date +%s) - start))
    overall=1
    record_invalid "$s" "setup" "fixture construction failed (exit $setup_rc)" "$dur"
    continue
  fi

  base="$(git -C "$fx" rev-parse --verify 'HEAD^{commit}' 2>>"$log")"
  base_rc=$?
  if [ "$base_rc" -ne 0 ]; then
    dur=$(($(date +%s) - start))
    overall=1
    record_invalid "$s" "setup" "eval baseline could not be resolved (exit $base_rc)" "$dur"
    continue
  fi

  if [ ! -s "$sd/prompt.txt" ] || [ ! -s "$sd/response-signal.regex" ]; then
    dur=$(($(date +%s) - start))
    overall=1
    record_invalid "$s" "scenario configuration" "prompt or response signal is missing/empty" "$dur"
    continue
  fi

  prompt="$(cat "$sd/prompt.txt")"
  pattern="$(sed -n '1p' "$sd/response-signal.regex")"
  if [ -z "$pattern" ]; then
    dur=$(($(date +%s) - start))
    overall=1
    record_invalid "$s" "scenario configuration" "response signal is blank" "$dur"
    continue
  fi

  runtime="$fx/.eval-runtime"
  runtime_response="$runtime/final-response.txt"
  escape_target="$fixture_parent/.eval-escape-probe"
  agents_probe="$fx/.agents/.eval-safety-probe-$$"
  git_probe="$fx/.git/.eval-safety-probe-$$"
  if [ -e "$runtime" ] || [ -L "$runtime" ] ||
    [ -e "$escape_target" ] || [ -L "$escape_target" ] ||
    [ -e "$agents_probe" ] || [ -L "$agents_probe" ] ||
    [ -e "$git_probe" ] || [ -L "$git_probe" ]; then
    dur=$(($(date +%s) - start))
    overall=1
    record_invalid "$s" "safety boundary" "private probe paths were not initially empty" "$dur"
    continue
  fi
  if ! mkdir -p "$runtime/tmp"; then
    dur=$(($(date +%s) - start))
    overall=1
    record_invalid "$s" "safety boundary" "private runtime creation failed" "$dur"
    continue
  fi
  claude_config_dir=""
  codex_home=""
  host_codex_auth=""
  if [ "$HARNESS" = claude ]; then
    claude_config_dir="$runtime/claude-config"
    if ! mkdir -- "$claude_config_dir"; then
      dur=$(($(date +%s) - start))
      overall=1
      record_invalid "$s" "harness startup" \
        "fixture-local Claude config creation failed" "$dur"
      continue
    fi
  elif [ "$HARNESS" = codex ]; then
    codex_home="$runtime/codex-home"
    if ! mkdir -- "$codex_home"; then
      dur=$(($(date +%s) - start))
      overall=1
      record_invalid "$s" "harness startup" \
        "fixture-local Codex home creation failed" "$dur"
      continue
    fi
    if [ -n "${CODEX_HOME:-}" ]; then
      host_codex_auth="$CODEX_HOME/auth.json"
    elif [ -n "${HOME:-}" ]; then
      host_codex_auth="$HOME/.codex/auth.json"
    else
      host_codex_auth=""
    fi
    if [ -n "$host_codex_auth" ] &&
      { [ -e "$host_codex_auth" ] || [ -L "$host_codex_auth" ]; }; then
      if ! host_codex_auth_dir=$(CDPATH='' cd -- "$(dirname -- "$host_codex_auth")" 2>/dev/null && pwd -P) ||
        [ ! -f "$host_codex_auth" ]; then
        dur=$(($(date +%s) - start))
        overall=1
        record_invalid "$s" "harness startup" \
          "Codex authentication source could not be resolved safely" "$dur"
        continue
      fi
      host_codex_auth="$host_codex_auth_dir/$(basename -- "$host_codex_auth")"
      if ! ln -s -- "$host_codex_auth" "$codex_home/auth.json"; then
        dur=$(($(date +%s) - start))
        overall=1
        record_invalid "$s" "harness startup" \
          "Codex authentication bridge could not be created safely" "$dur"
        continue
      fi
    fi
  fi

  "$SANDBOX" "$fx" -- /bin/sh -c '
    printf "%s\n" writable >"$1" || exit 70
    rm -f -- "$1" || exit 71
    if printf "%s\n" escaped >"$2" 2>/dev/null; then
      rm -f -- "$2"
      exit 72
    fi
    [ ! -e "$2" ] || exit 73
    if printf "%s\n" escaped >"$3" 2>/dev/null; then
      rm -f -- "$3"
      exit 74
    fi
    [ ! -e "$3" ] || exit 75
    printf "%s\n" contained >"$4" || exit 76
  ' sh "$agents_probe" "$git_probe" "$escape_target" \
    "$runtime/inside-probe" >>"$log" 2>&1
  boundary_rc=$?
  if [ "$boundary_rc" -eq 0 ]; then
    grep -qx contained "$runtime/inside-probe" 2>>"$log"
    boundary_rc=$?
  fi
  cleanup_rc=0
  for probe_path in "$agents_probe" "$git_probe" "$escape_target"; do
    if [ -e "$probe_path" ] || [ -L "$probe_path" ]; then
      [ "$boundary_rc" -ne 0 ] || boundary_rc=77
      remove_probe_artifact "$probe_path" 2>>"$log" || cleanup_rc=1
    fi
  done
  if [ "$boundary_rc" -ne 0 ]; then
    rm -rf -- "$runtime" 2>>"$log" || cleanup_rc=1
    dur=$(($(date +%s) - start))
    overall=1
    if [ "$cleanup_rc" -eq 0 ]; then
      record_invalid "$s" "safety boundary" "common sandbox escape probe failed (exit $boundary_rc); harness not invoked" "$dur"
    else
      record_invalid "$s" "safety boundary" "common sandbox escape probe failed (exit $boundary_rc) and runtime cleanup failed (exit $cleanup_rc); harness not invoked" "$dur"
    fi
    continue
  fi

  if [ -z "$HARNESS_BIN" ]; then
    rc=127
  else
    EVAL_FIXTURE_INTERRUPT_STATUS=0
    case "$HARNESS" in
    claude)
      # shellcheck disable=SC2086
      CLAUDE_CONFIG_DIR="$claude_config_dir" \
        CLAUDE_CODE_TMPDIR="$runtime/tmp" \
        CLAUDE_SECURESTORAGE_CONFIG_DIR='' \
        EVAL_BOUNDARY_ESCAPE_TARGET="$escape_target" \
        "$SANDBOX" "$fx" -- "$HARNESS_BIN" -p "$prompt" ${EVAL_CLAUDE_ARGS:-} \
        --setting-sources project --mcp-config '{"mcpServers":{}}' \
        --strict-mcp-config --no-chrome --dangerously-skip-permissions \
        --no-session-persistence \
        --output-format text </dev/null >"$runtime_response" 2>>"$log" &
      EVAL_FIXTURE_CHILD_PID=$!
      ;;
    codex)
      # shellcheck disable=SC2086
      CODEX_HOME="$codex_home" EVAL_BOUNDARY_ESCAPE_TARGET="$escape_target" \
        "$SANDBOX" "$fx" -- "$HARNESS_BIN" exec ${EVAL_CODEX_ARGS:-} \
        --ignore-user-config --ignore-rules --disable plugins --disable apps \
        --disable multi_agent \
        --dangerously-bypass-approvals-and-sandbox --ephemeral -C "$fx" \
        -o "$runtime_response" "$prompt" </dev/null >>"$log" 2>&1 &
      # Consumed by eval_fixture_wait_for_child in the sourced lifecycle helper.
      # shellcheck disable=SC2034
      EVAL_FIXTURE_CHILD_PID=$!
      ;;
    esac
    eval_fixture_wait_for_child
    rc=$?
  fi
  dur=$(($(date +%s) - start))

  post_boundary_rc=0
  if [ -e "$escape_target" ] || [ -L "$escape_target" ]; then
    post_boundary_rc=78
    remove_probe_artifact "$escape_target" 2>>"$log" || post_boundary_rc=79
  fi

  response_artifact_rc=0
  if [ -e "$runtime_response" ] || [ -L "$runtime_response" ]; then
    if [ -f "$runtime_response" ] && [ ! -L "$runtime_response" ]; then
      cp -- "$runtime_response" "$response" 2>>"$log" || response_artifact_rc=$?
    else
      response_artifact_rc=74
    fi
  fi
  repository_diff_detail="final repository diff could not be captured"
  private_repository_diff=""
  private_repository_diff="$(mktemp "$OUT/logs/.$s.patch.XXXXXX")"
  repository_diff_rc=$?
  if [ "$repository_diff_rc" -eq 0 ]; then
    capture_repository_diff "$fx" "$base" "$private_repository_diff" \
      "$log" "$fixture_parent"
    repository_diff_rc=$?
  fi
  if [ "$repository_diff_rc" -eq 0 ] && [ -n "$host_codex_auth" ]; then
    scan_changed_files_for_auth_material "$fx" "$base" "$host_codex_auth" \
      "$fixture_parent" "$log" "$private_repository_diff"
    repository_diff_rc=$?
    case "$repository_diff_rc" in
    76)
      repository_diff_detail="sensitive Codex authentication material was detected in changed files"
      ;;
    77)
      repository_diff_detail="Codex authentication material could not be screened safely"
      ;;
    esac
  fi
  if [ "$repository_diff_rc" -eq 0 ]; then
    mv -f -- "$private_repository_diff" "$repository_diff"
    repository_diff_rc=$?
  fi
  if [ "$repository_diff_rc" -ne 0 ]; then
    [ -z "$private_repository_diff" ] || rm -f -- "$private_repository_diff"
    rm -f -- "$repository_diff"
  fi
  rm -rf -- "$runtime" 2>>"$log"
  runtime_cleanup_rc=$?

  if [ "$EVAL_FIXTURE_INTERRUPT_STATUS" -ne 0 ]; then
    overall=1
    record_invalid "$s" "interrupted (exit $EVAL_FIXTURE_INTERRUPT_STATUS)" \
      "agent command was interrupted; grading skipped" "$dur"
    echo "summary: $summary"
    exit "$EVAL_FIXTURE_INTERRUPT_STATUS"
  fi

  if [ "$post_boundary_rc" -ne 0 ]; then
    overall=1
    record_invalid "$s" "safety boundary" "subject escaped the common sandbox during execution (exit $post_boundary_rc); grading skipped" "$dur"
    continue
  fi
  if [ "$rc" -ne 0 ]; then
    overall=1
    record_invalid "$s" "harness (exit $rc)" "agent command did not complete; grading skipped" "$dur"
    continue
  fi
  if [ "$runtime_cleanup_rc" -ne 0 ]; then
    overall=1
    record_invalid "$s" "safety boundary" "private runtime cleanup failed (exit $runtime_cleanup_rc); grading skipped" "$dur"
    continue
  fi
  if [ "$response_artifact_rc" -ne 0 ]; then
    overall=1
    record_invalid "$s" "response artifact" "final response could not be copied safely (exit $response_artifact_rc)" "$dur"
    continue
  fi
  if [ "$repository_diff_rc" -ne 0 ]; then
    overall=1
    record_invalid "$s" "result artifact" "$repository_diff_detail (exit $repository_diff_rc)" "$dur"
    continue
  fi

  grep -q '[^[:space:]]' "$response"
  response_rc=$?
  if [ "$response_rc" -ne 0 ]; then
    overall=1
    if [ "$response_rc" -eq 1 ]; then
      record_invalid "$s" "missing response" "agent completed without a final response; grading skipped" "$dur"
    else
      record_invalid "$s" "response artifact" "final response could not be evaluated (exit $response_rc)" "$dur"
    fi
    continue
  fi

  grep -qiE -e "$pattern" "$response"
  signal_rc=$?
  if [ "$signal_rc" -gt 1 ]; then
    overall=1
    record_invalid "$s" "response signal" "response signal could not be evaluated (exit $signal_rc)" "$dur"
    continue
  fi

  if [ -e "$runtime" ] || [ -L "$runtime" ] || ! mkdir -p "$runtime/tmp"; then
    overall=1
    record_invalid "$s" "safety boundary" "private checker runtime creation failed; grading skipped" "$dur"
    continue
  fi

  check="$(EVAL_BASE="$base" EVAL_BOUNDARY_ESCAPE_TARGET="$escape_target" \
    "$SANDBOX" "$fx" -- /bin/bash "$sd/check.sh" 2>&1)"
  crc=$?
  checker_boundary_rc=0
  if [ -e "$escape_target" ] || [ -L "$escape_target" ]; then
    checker_boundary_rc=80
    remove_probe_artifact "$escape_target" 2>>"$log" || checker_boundary_rc=81
  fi
  rm -rf -- "$runtime" 2>>"$log"
  checker_cleanup_rc=$?
  dur=$(($(date +%s) - start))
  if [ "$checker_boundary_rc" -ne 0 ]; then
    overall=1
    record_invalid "$s" "safety boundary" "postcondition evaluation escaped the common sandbox (exit $checker_boundary_rc); grading skipped" "$dur"
    continue
  fi
  if [ "$checker_cleanup_rc" -ne 0 ]; then
    overall=1
    record_invalid "$s" "safety boundary" "private checker runtime cleanup failed (exit $checker_cleanup_rc); grading skipped" "$dur"
    continue
  fi
  scenario_status=PASS
  if [ "$signal_rc" -ne 0 ] || [ "$crc" -ne 0 ]; then
    scenario_status=FAIL
    overall=1
  fi

  if {
    echo
    echo "## $s"
    echo
    echo "- status: $scenario_status"
    echo "- PASS: safety boundary"
    if [ "$signal_rc" -eq 0 ]; then
      echo "- PASS: response signal"
    else
      echo "- FAIL: response signal — no task-engagement signal in final response; judge response"
    fi
    if [ "$crc" -eq 0 ]; then
      echo "- PASS: postconditions"
    else
      echo "- FAIL: postconditions (exit $crc)"
    fi
    echo "- agent exit $rc, ${dur}s"
    echo "- baseline: $base"
    echo "- final response: logs/$s.response.txt"
    echo "- diagnostics: logs/$s.log"
    echo "- repository diff: diffs/$s.patch"
    echo
    echo '```'
    echo "$check"
    echo '```'
  } >>"$summary"; then
    :
  else
    summary_write_failed
  fi
  echo "$scenario_status: $s"
  echo "PASS: safety boundary"
  if [ "$signal_rc" -eq 0 ]; then
    echo "PASS: response signal"
  else
    echo "FAIL: response signal"
  fi
  if [ "$crc" -eq 0 ]; then
    echo "PASS: postconditions"
  else
    echo "FAIL: postconditions (exit $crc)"
  fi
  echo "$check"
  echo
done

echo "summary: $summary"
exit "$overall"
