# Recorded counterexamples

At historical revision cache-v2, witness LOW used integer -1 through both
modes, expected [0,100], and observed -1. Reproduce:
`python3 tests/witness_ttl.py LOW`.
Result: falsified
