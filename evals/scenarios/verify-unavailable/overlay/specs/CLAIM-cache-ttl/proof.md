## Scope
app/cache_policy.py and app/cache_export.py, both supported export modes.
## Model and quantifiers
Sequential calls with exact Python integer inputs; no subclasses or other modes.
## Axioms
Python integer comparison and min/max semantics.
## Argument
1. `code` — ttl clamps integer inputs to [0, 100].
2. `code` — export_ttl delegates both modes to ttl without changing the value.
3. `test` — tests/witness_ttl.py checks both boundaries through both modes.
## Residuals
Inputs and modes outside the stated quantifiers are excluded.
## Weakest links
The guard and both call paths require review; finite examples alone do not
establish the quantified property.
