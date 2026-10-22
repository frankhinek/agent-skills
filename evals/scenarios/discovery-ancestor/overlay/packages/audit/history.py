import json
from pathlib import Path

HISTORY = Path("history/events.jsonl")


def append_event(event):
    HISTORY.parent.mkdir(parents=True, exist_ok=True)
    with HISTORY.open("a") as handle:
        handle.write(json.dumps(event) + "\n")


def read_events():
    if not HISTORY.exists():
        return []
    return [json.loads(line) for line in HISTORY.read_text().splitlines()]
