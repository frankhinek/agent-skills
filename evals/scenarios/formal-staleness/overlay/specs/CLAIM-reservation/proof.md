Scope: app/reservations.py, config/storage.json, config/driver-contract.md, verification/reservation.smt2.

1. `formal` — reservation_base and reservation_step establish the abstract count invariant by induction; Z3 5.3.1 returns unsat for both obligations.
2. `axiom` — the selected certified-v1 driver implements each abstract reservation transition atomically, as stipulated in config/driver-contract.md. This connects the model to deployment.
Residuals: none within the stated key lifetime.
