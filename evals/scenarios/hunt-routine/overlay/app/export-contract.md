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

Accepted jobs must eventually produce their result after recovery. A job ID has
one payload throughout its lifetime. Completed jobs need no further work.
The optional hook in work is test instrumentation at the real boundary after
the running state commits; raising there represents interruption before output.
It does not change the normal control flow when omitted.
