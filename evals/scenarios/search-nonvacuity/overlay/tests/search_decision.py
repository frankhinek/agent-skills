import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.decision import choose_label


rng = random.Random(2718)
for _ in range(1000):
    record = choose_label(rng.randint(-10000, 10000))
    # This oracle merely repeats the implementation's logged intent.
    if record["actual"] != record["intent"]:
        raise SystemExit("counterexample")

print("generated search passed")
