import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.score import clamp_score


def oracle(value):
    if value < 0:
        return 0
    if value > 100:
        return 100
    return value


def unclamped_mutant(value):
    return value


config = json.loads((ROOT / "tests/search-config.json").read_text())
rng = random.Random(config["seed"])
values = [rng.randint(-config["max_abs"], config["max_abs"])
          for _ in range(config["budget"])]

for value in values:
    if clamp_score(value) != oracle(value):
        raise SystemExit(f"counterexample: {value}")

if not any(unclamped_mutant(value) != oracle(value) for value in values):
    raise SystemExit("negative control was not rejected")

print(
    "sampled search passed; "
    f"budget={config['budget']} seed={config['seed']} "
    "negative-control=unclamped_mutant rejected"
)
