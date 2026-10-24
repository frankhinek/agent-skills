import sqlite3


class Queue:
    """One worker, durable jobs; restart after failure."""

    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS jobs (
                id TEXT PRIMARY KEY, payload TEXT, state TEXT
            );
            CREATE TABLE IF NOT EXISTS results (id TEXT PRIMARY KEY, payload TEXT);
        """)
        self.recover()

    def recover(self):
        # The process-local worker slot starts empty.
        with self.db:
            self.db.execute("UPDATE jobs SET state = 'pending' WHERE state = 'running'")

    def submit(self, job_id, payload):
        with self.db:
            self.db.execute("INSERT OR IGNORE INTO jobs VALUES (?, ?, 'pending')",
                            (job_id, payload))
        return {"accepted": True, "id": job_id}

    def work(self, after_claim=None):
        row = self.db.execute(
            "SELECT id, payload FROM jobs WHERE state IN ('pending', 'running') ORDER BY id LIMIT 1"
        ).fetchone()
        if row is None:
            return False
        with self.db:
            self.db.execute("UPDATE jobs SET state = 'running' WHERE id = ?", (row[0],))
        if after_claim:
            after_claim()
        with self.db:
            self.db.execute("INSERT INTO results VALUES (?, ?)", row)
            self.db.execute("UPDATE jobs SET state = 'done' WHERE id = ?", (row[0],))
        return True

    def result(self, job_id):
        row = self.db.execute("SELECT payload FROM results WHERE id = ?", (job_id,)).fetchone()
        return row[0] if row else None

    def close(self):
        self.db.close()
