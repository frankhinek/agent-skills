#!/usr/bin/env bash
# Run the linked-records behavioral evals against a harness.
#
# Usage: run.sh <claude|codex> [scenario ...]     (default: all scenarios)
#
# Each scenario: build a fresh fixture, apply the scenario overlay if any,
# run the harness headlessly with the scenario prompt, then run check.sh
# (mechanical postconditions) inside the fixture. Final responses and
# diagnostic logs go to results/<date>-<harness>/logs/ (gitignored); the
# summary is committed.
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
OUT="$EVALS/results/$DATE-$HARNESS${EVAL_LABEL:+-$EVAL_LABEL}"
summary="$OUT/summary.md"

write_summary_header() {
  printf '%s\n' \
    '---' \
    "summary: \"Records the $HARNESS_NAME linked-records behavioral eval run from $DATE.\"" \
    'read_when:' \
    '  - Comparing linked-records behavior across harnesses or model versions' \
    "  - Investigating this eval run's mechanical and escalation results" \
    "title: \"$HARNESS_NAME Eval Run — $DATE\"" \
    '---' \
    >"$summary"
}

if [ "${#UNKNOWN_SCENARIOS[@]}" -gt 0 ] || [ "${#SCENARIOS[@]}" -eq 0 ]; then
  mkdir -p "$OUT"
  write_summary_header
  {
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
  } >>"$summary"

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

mkdir -p "$OUT/logs"
write_summary_header

if ! safety_profile="$("$SANDBOX" --profile-id 2>/dev/null)" || [ -z "$safety_profile" ]; then
  safety_profile="unavailable"
fi
if ! sandbox_version="$("$SANDBOX" --backend-version 2>/dev/null)" || [ -z "$sandbox_version" ]; then
  sandbox_version="unavailable"
fi

{
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
  echo "- safety checks: .agents write and .git/sibling denial before subject; sibling escape canaries after subject and postconditions"
  echo "- final responses and diagnostics: logs/"
  echo "- mechanical checks below; judge escalation quality from final responses"
} >>"$summary"

record_invalid() {
  local scenario="$1"
  local reason="$2"
  local detail="$3"
  local duration="$4"
  {
    echo
    echo "## $scenario"
    echo
    echo "- status: INVALID: $reason"
    echo "- detail: $detail"
    echo "- duration: ${duration}s"
    echo "- diagnostics: logs/$scenario.log"
  } >>"$summary"
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
  : >"$log"
  : >"$response"
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
      EVAL_BOUNDARY_ESCAPE_TARGET="$escape_target" \
        "$SANDBOX" "$fx" -- "$HARNESS_BIN" -p "$prompt" ${EVAL_CLAUDE_ARGS:-} \
        --dangerously-skip-permissions --no-session-persistence \
        --output-format text </dev/null >"$runtime_response" 2>>"$log" &
      EVAL_FIXTURE_CHILD_PID=$!
      ;;
    codex)
      # shellcheck disable=SC2086
      EVAL_BOUNDARY_ESCAPE_TARGET="$escape_target" \
        "$SANDBOX" "$fx" -- "$HARNESS_BIN" exec ${EVAL_CODEX_ARGS:-} \
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

  {
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
    echo
    echo '```'
    echo "$check"
    echo '```'
  } >>"$summary"
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
