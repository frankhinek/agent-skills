from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.cache_updates import Cache

cache = Cache()

def interrupt():
    raise RuntimeError("interrupted after append")

try:
    cache.apply("request-1", "value", after_append=interrupt)
except RuntimeError:
    pass
cache.apply("request-1", "value")
print(f"versions={cache.versions!r}, receipts={cache.receipts!r}")
assert len(cache.versions) <= 1, "same command appended twice"
