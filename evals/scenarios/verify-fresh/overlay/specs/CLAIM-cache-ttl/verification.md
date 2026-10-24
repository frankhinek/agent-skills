# Previous verification

At historical revision cache-v1, reviewer A checked raw and JSON exports and
reported pass; both modes were believed to use the clamp.
Result: pass

A subsequent report at historical revision cache-v2 recorded witness LOW:
`python3 tests/witness_ttl.py LOW` returned raw=-1 for input -1 in raw mode.
Expected [0,100], observed -1. No repair or resolution was recorded.
Result: falsified
