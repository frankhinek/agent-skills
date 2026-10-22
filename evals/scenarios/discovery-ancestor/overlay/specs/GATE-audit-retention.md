# GATE-audit-retention: Recorded audit events are retained

## Gate

Every event recorded in `history/events.jsonl` must remain in that file,
unchanged and in order. Agents must not implement automatic deletion or
replacement of recorded events.

## Justification

The owner needs a complete local event history to reconstruct past actions.
