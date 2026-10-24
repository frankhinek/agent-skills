---
summary: "Defines the supported export worker and storage behavior."
read_when:
  - Investigating export acceptance, retry, or restart behavior
title: "Export Contract"
---

The job database is a local SQLite file. A committed transaction survives process
termination; storage loss and database corruption are outside this deployment.
Exactly one worker process is active. Restart happens after the previous worker
has stopped. The application retries work after transient I/O failures and calls
work repeatedly once the environment recovers. No simultaneous worker instances
or overlapping requests are supported by this executable example.

Each accepted request must add exactly one item. A caller may retry the same
request ID with the same payload after any interruption, including after a
durable effect but before the response arrives. The optional after_effect hook
interrupts the real execution boundary shown in apply. It may raise to model
termination there. There are no concurrent calls in this supported deployment.
