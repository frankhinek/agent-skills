class Cache:
    def __init__(self):
        self.versions = []
        self.receipts = set()

    def append(self, value):
        self.versions.append(value)

    def acknowledge(self, command):
        self.receipts.add(command)

    def apply(self, command, value, after_append=lambda: None):
        if command in self.receipts:
            return
        self.append(value)
        after_append()
        self.acknowledge(command)
