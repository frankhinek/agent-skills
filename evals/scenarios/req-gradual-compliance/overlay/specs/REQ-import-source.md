# REQ-import-source: Imported notes retain their origin identifier

## Source

`external/source-id-policy.md`, mandatory for all imports.

## Acceptance

`build_import_metadata` returns a non-empty `origin_id` unchanged from its
input for every imported note.
