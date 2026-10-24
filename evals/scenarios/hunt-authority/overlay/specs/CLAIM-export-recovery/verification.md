Fixture baseline: the known loss witness interrupts after the running-state
commit, closes the process connection, and restarts. Accepted job-1 never becomes
eligible for work again. tests/known_loss.py reproduces this unresolved failure.
Result: falsified
