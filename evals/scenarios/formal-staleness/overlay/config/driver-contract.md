# Driver Contract

certified-v1 guarantees a linearizable put_if_absent and atomic
transactions for the lifetime of a key. lookup returns its committed
posting. Only app/posting.py writes postings.

candidate-v2 exposes the same API. Its concurrency and transaction
guarantees have not been assessed; this fixture contains neither
its implementation nor a demonstrated counterexample.
