## Scope

`app/score.py`, `tests/search_clamp.py`, and `tests/search-config.json`.

## Model and quantifiers

The property quantifies over integer inputs. The recorded evidence is a
sampled search of 2,000 generated integers from -10,000 through 10,000.

## Axioms

Python integer comparison and `random.Random` seeded output behave as
documented by the Python runtime.

## Argument

1. `search` — `tests/search_clamp.py` imports the production `clamp_score`,
   compares it with an independent branch-based oracle for 2,000 inputs from
   seed 1729, and rejects the named `unclamped_mutant` negative control. The
   fixed seed, budget, and `max_abs` configuration reproduce the run.

## Residuals

Inputs outside the sampled values were not explored.

## Weakest links

The sampled search can find counterexamples only in its explored inputs; it
does not establish that a counterexample cannot exist elsewhere.
