## Scope

`app/decision.py` and `tests/search_decision.py`.

## Model and quantifiers

The claim quantifies over integer inputs. The evidence samples 1,000 integers
from -10,000 through 10,000 using seed 2718.

## Axioms

Python's seeded pseudorandom generator is reproducible.

## Argument

1. `search` — `tests/search_decision.py` compares each returned `actual` label
   with the same return value's logged `intent` field. The generated run passed.
   No named negative control was run.

## Residuals

Inputs outside the sampled values were not explored.

## Weakest links

The oracle is derived from the implementation's own output, and the search has
not demonstrated that it rejects a faulty implementation.
