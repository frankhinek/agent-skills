# SPEC-published-record: Publisher and reader share a text field

## Record justification

Record construction in `packages/publisher/payload.py` and consumption in
`packages/reader/render.py` are independently owned, so neither package alone
can preserve their shared payload contract.

Records produced by `build_record` contain note content under `text`;
`render_record` reads that field and returns its value.

This contract constrains
[ARCH-publisher](../../publisher/specs/ARCH-publisher.md).
