# CLAIM-score-export: Exported integer scores stay bounded

For every raw with type(raw) is int, when export_score(raw) returns, the
score field in Python json.loads of its JSON result has type(score) is int
and lies between 0 and 100 inclusive. Booleans and int subclasses are outside
this input domain.
