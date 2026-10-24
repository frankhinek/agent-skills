from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.export_queue import Queue

class Interrupted(Exception):
    pass

def interrupt():
    raise Interrupted()

with tempfile.TemporaryDirectory() as scratch:
    path = str(Path(scratch) / "jobs.db")
    worker = Queue(path)
    assert worker.submit("job-1", "hello")["accepted"]
    try:
        worker.work(after_claim=interrupt)
    except Interrupted:
        pass
    worker.close()
    restarted = Queue(path)
    restarted.work()
    assert restarted.result("job-1") == "hello", "accepted work abandoned after restart"
    restarted.close()
