def choose_label(value):
    """Return the decision plus the implementation's stated intent."""
    label = "even" if value % 2 == 0 else "odd"
    return {"intent": label, "actual": label}
