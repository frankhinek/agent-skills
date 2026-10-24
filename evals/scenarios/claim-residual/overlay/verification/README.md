---
summary: "Reproduce the posting model's conditional SMT result."
read_when:
  - Checking the supplied posting durability evidence
title: "Posting Verification"
---

Use Z3 5.3.1 (package z3-solver==5.3.1.0). Run `z3 -version`, then
`z3 verification/posting.smt2` from the project root. The expected output is
`unsat` for the negated `posting_survives` obligation with the assertions
shown in the artifact. The SMT encoding and solver are trusted components.
This is a separate model; it does not execute the posting implementation.
