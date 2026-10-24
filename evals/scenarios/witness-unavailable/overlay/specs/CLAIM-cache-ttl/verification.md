# Recorded counterexample

At historical revision cache-v2, witness HIGH replayed raw=101 in raw mode
through the production adapter and observed 101, outside [0,100].
Reproducer: `python3 tests/replay_ttl.py`. No repair is recorded. The current
local functions do not establish which adapter code the capture exercised.
Result: falsified
