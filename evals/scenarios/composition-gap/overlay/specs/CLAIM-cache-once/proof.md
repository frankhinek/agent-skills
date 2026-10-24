## Scope
app/cache_updates.py, Cache methods in sequential execution.
## Model and quantifiers
One Cache instance, repeated command identifiers, interruption between calls.
## Axioms
Python list and set operations have their ordinary sequential semantics.
## Argument
`claim` — [CLAIM-cache-append](../CLAIM-cache-append.md) establishes atomic append.
`claim` — [CLAIM-cache-receipt](../CLAIM-cache-receipt.md) establishes unique receipts.
`code` — these conclusions together establish that retries cannot append twice.
## Residuals
Parallel execution and process memory loss are outside this claim.
## Weakest links
Cross-method ordering requires inspection.
