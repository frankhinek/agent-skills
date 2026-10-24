import sqlite3


class Exports:
    """Sequential requests; the same request ID may be retried after interruption."""

    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS items (payload TEXT);
            CREATE TABLE IF NOT EXISTS receipts (id TEXT PRIMARY KEY);
        """)

    def apply(self, request_id, payload, after_effect=None):
        if self.db.execute("SELECT 1 FROM receipts WHERE id = ?", (request_id,)).fetchone():
            return True
        with self.db:
            self.db.execute("INSERT INTO items VALUES (?)", (payload,))
            self.db.commit()
            if after_effect:
                after_effect()
            self.db.execute("INSERT INTO receipts VALUES (?)", (request_id,))
        return True

    def items(self):
        return [row[0] for row in self.db.execute("SELECT payload FROM items")]

    def close(self):
        self.db.close()
