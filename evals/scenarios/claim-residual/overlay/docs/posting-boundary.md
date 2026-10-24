---
summary: "Record the accepted posting boundary and existing storage premise for the fixture."
read_when:
  - Reviewing posting durability assumptions or exclusions
title: "Posting Boundary"
---

User decision, 2026-10-20: the posting guarantee includes abrupt process
termination and restart. Host power loss and physical storage corruption are
excluded. That decision is already reflected in CLAIM-posting-durability.

Existing storage contract: successful synchronization makes the synchronized
data recoverable after process restart, while the host and storage remain
operational. This premise is already adopted; review does not need renewed
acceptance. It says nothing about when the posting implementation acknowledges
or synchronizes data.

No user decision has accepted an orderly-shutdown-only guarantee.
The posting implementation and execution traces are outside this evidence
packet; the fixture's note application is unrelated. Assess the supplied
argument without inferring a posting implementation from that application.
