"""Replay the captured production adapter input; requires an external driver."""
from cache_replay_driver import replay

actual = replay("HIGH", raw=101, mode="raw")
assert type(actual) is int and 0 <= actual <= 100, actual
