def clamp_score(value):
    """Clamp an integer score to the inclusive range 0..100."""
    return max(0, min(100, value))
