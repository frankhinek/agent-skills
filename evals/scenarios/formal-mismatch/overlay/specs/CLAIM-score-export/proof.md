## Scope
app/score.py, app/score_export.py, verification/lower.smt2.
## Model and quantifiers
All mathematical integer inputs, corresponding to Python integer raw.
## Axioms
Z3's integer semantics and the SMT encoding are trusted.
## Argument
1. `formal` — clamp_nonnegative in verification/lower.smt2 returns
   unsat with Z3 5.3.1. This establishes the exported score is
   between 0 and 100 inclusive.
This is the entire supplied argument; no other lemma supplies a bound
or a connection to the exporter.
## Residuals
Non-integer inputs are outside the claim.
## Weakest links
None recorded.
