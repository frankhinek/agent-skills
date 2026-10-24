---
summary: "Reproduce the fixture's SMT obligation checks."
read_when:
  - Checking the fixture's formal evidence
title: "Executable Verification"
---

Use Z3 5.3.1 (package z3-solver==5.3.1.0). Run `z3 -version`, then
`z3 verification/identity.smt2` from the project root. Each `unsat`
discharges the corresponding negated obligation over mathematical
integers. These are symbolic obligations, not sampled test inputs.
The SMT source and solver semantics are part of the trusted base.
