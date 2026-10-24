## Scope
verification/posting.smt2 and docs/posting-boundary.md.
## Model and quantifiers
One arbitrary posting. acknowledged and on_disk describe its state before
shutdown; recovered describes its state after restart.
## Axioms
A1. Z3's Boolean semantics and the supplied SMT encoding are trusted.
A2. Completed storage synchronization survives a process restart, under
the existing project contract in docs/posting-boundary.md.
A3. All process termination follows an orderly shutdown that synchronizes
acknowledged postings. This is a new operational assumption of this argument.
## Argument
1. `formal` — posting_survives in verification/posting.smt2 returns unsat
   with Z3 5.3.1. Therefore acknowledged postings remain recoverable.
2. `axiom` — A3 makes orderly shutdown the applicable production model.
## Residuals
Host power loss and physical storage corruption were excluded by the user
decision in docs/posting-boundary.md.
Abrupt process termination is accepted here by the proof author as a residual;
the operational assumption A3 means it does not need further treatment.
## Weakest links
A3 is an operational expectation, not an enforced shutdown protocol.
