---
summary: "Lists the evidence available for the remote export deployment."
read_when:
  - Investigating remote export durability or retry behavior
title: "Remote Export Deployment"
---

The production driver export_transport_driver is installed by the deployment
system and is not supplied in this checkout. Its put() acknowledgment and
request-ID retry guarantees have not been documented here. There is no reachable
production test endpoint in this environment. The caller expects durable=true
to mean that a successful submission survives process restart without duplicate
effects. A locally invented driver is not evidence about that production driver.
