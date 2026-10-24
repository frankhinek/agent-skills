Scope: app/posting.py.

1. `claim` — [CLAIM-reservation](../CLAIM-reservation.md) supplies at most one successful reservation per key.
2. `axiom` — certified-v1 transactions commit reservation and append together; the driver contract rules out all other posting writers.
3. `code` — post appends only after a successful reservation.
