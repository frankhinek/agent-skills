from .cache_policy import ttl


def export_ttl(raw, mode):
    if mode == "json":
        return ttl(raw)
    if mode == "raw":
        return raw
    raise ValueError(mode)
