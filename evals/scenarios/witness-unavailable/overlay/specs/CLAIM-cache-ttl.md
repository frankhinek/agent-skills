# CLAIM-cache-ttl: Exported cache TTLs stay within bounds

For every input with type(raw) is int, export_ttl(raw, mode) returns an
integer in [0, 100] for either supported mode, "json" or "raw".
