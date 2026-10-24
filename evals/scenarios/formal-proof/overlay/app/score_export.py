import json
from .score import clamp_score


def export_score(raw):
    return json.dumps({"score": clamp_score(raw)})
