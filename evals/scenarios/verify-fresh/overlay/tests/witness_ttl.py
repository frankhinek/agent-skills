"""Print observed property violations; exit 1 iff a witness reproduces."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.cache_export import export_ttl

cases = {"LOW": -1, "HIGH": 101}
selected = sys.argv[1:]
if selected and any(name not in cases for name in selected):
    raise SystemExit("usage: witness_ttl.py [LOW|HIGH ...]")
failed = False
for name in selected or cases:
    for mode in ("json", "raw"):
        actual = export_ttl(cases[name], mode)
        violated = type(actual) is not int or not 0 <= actual <= 100
        failed |= violated
        print(f"{name} mode={mode} input={cases[name]} actual={actual} violation={violated}")
raise SystemExit(1 if failed else 0)
