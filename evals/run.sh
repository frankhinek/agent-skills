#!/usr/bin/env bash
# Run the linked-records behavioral evals against a harness.
#
# Usage: run.sh <claude|codex> [scenario ...]     (default: all scenarios)
#
# Each scenario: build a fresh fixture, apply the scenario overlay if any,
# run the harness headlessly with the scenario prompt, then run check.sh
# (mechanical postconditions) inside the fixture. Transcripts go to
# results/<date>-<harness>/logs/ (gitignored); the summary is committed.
set -uo pipefail

EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="${1:?usage: run.sh <claude|codex> [scenario ...]}"
shift || true

DATE="$(date +%Y-%m-%d)"
OUT="$EVALS/results/$DATE-$HARNESS${EVAL_LABEL:+-$EVAL_LABEL}"
mkdir -p "$OUT/logs"

if [ $# -gt 0 ]; then
  SCENARIOS=("$@")
else
  SCENARIOS=()
  for d in "$EVALS/scenarios"/*/; do SCENARIOS+=("$(basename "$d")"); done
fi

summary="$OUT/summary.md"
{
  echo "# Eval run: $HARNESS, $DATE"
  echo
  case "$HARNESS" in
  claude) echo "- version: $(claude --version 2>/dev/null | head -1)" ;;
  codex) echo "- version: $(codex --version 2>/dev/null | head -1)" ;;
  esac
  [ -z "${EVAL_CLAUDE_ARGS:-}${EVAL_CODEX_ARGS:-}" ] ||
    echo "- pinned args: ${EVAL_CLAUDE_ARGS:-}${EVAL_CODEX_ARGS:-}"
  echo "- mechanical checks below; judge escalation quality from logs/"
  echo
} >"$summary"

overall=0
for s in "${SCENARIOS[@]}"; do
  sd="$EVALS/scenarios/$s"
  [ -d "$sd" ] || { echo "unknown scenario: $s" >&2; continue; }

  fx="$(mktemp -d)/fixture"
  "$EVALS/fixture.sh" "$fx"
  if [ -d "$sd/overlay" ]; then
    cp -R "$sd/overlay/." "$fx/"
    git -C "$fx" add -A
    git -C "$fx" commit -qm "overlay"
  fi

  prompt="$(cat "$sd/prompt.txt")"
  echo "== $s ($HARNESS) =="
  start="$(date +%s)"
  case "$HARNESS" in
  claude)
    # shellcheck disable=SC2086
    (cd "$fx" && claude -p "$prompt" --dangerously-skip-permissions ${EVAL_CLAUDE_ARGS:-}) \
      >"$OUT/logs/$s.log" 2>&1
    rc=$?
    ;;
  codex)
    # shellcheck disable=SC2086
    codex exec ${EVAL_CODEX_ARGS:-} -s workspace-write -C "$fx" "$prompt" \
      >"$OUT/logs/$s.log" 2>&1
    rc=$?
    ;;
  *)
    echo "unsupported harness: $HARNESS" >&2
    exit 2
    ;;
  esac
  dur=$(($(date +%s) - start))

  check="$(cd "$fx" && bash "$sd/check.sh" 2>&1)"
  crc=$?
  [ "$crc" -eq 0 ] || overall=1

  {
    echo "## $s"
    echo
    echo '```'
    echo "$check"
    echo '```'
    echo
    echo "- agent exit ${rc}, ${dur}s — transcript: logs/$s.log"
    echo
  } >>"$summary"
  echo "$check"
  echo
done

echo "summary: $summary"
exit "$overall"
