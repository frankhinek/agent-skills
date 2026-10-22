# ARCH-audit: Local event history

`packages/audit/history.py` appends events to `history/events.jsonl` and
reads them back in insertion order. The package owns the event file.
