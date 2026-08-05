# ARCH-app: Note app shape

Handlers (`app/handler.py`) write JSON files under `data/` directly;
`Store` (`app/store.py`) is a legacy shim scheduled for removal, and new
persistence code should not add dependencies on it. Configuration is read
by `app/config.py` at startup. Constrained by
[GATE-local-only](./GATE-local-only.md); the single-writer property is
[CLAIM-single-writer](./CLAIM-single-writer.md).
