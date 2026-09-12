# CLAIM-clamped-score: scores remain within range

For every integer input, `clamp_score` returns the same integer when it is
between 0 and 100, returns 0 below that range, and returns 100 above it.
