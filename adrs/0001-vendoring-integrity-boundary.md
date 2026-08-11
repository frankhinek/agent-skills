---
summary: "Records the portable inventory, provenance trust boundary, and transactional refresh design for vendored skills."
read_when:
  - Changing vendored-manifest semantics or local-edit detection
  - Modifying provenance validation, remote checks, or copy transactions
title: "Vendoring Integrity Boundary"
---

# Vendoring Integrity Boundary

Date: 2026-08-10
Status: Accepted

## Context

Project-level skill copies must refresh without silently discarding ordinary
local changes. Checks must remain portable across the supported macOS and Linux
shell environments. Provenance data is stored in the destination project and
therefore cannot be trusted to select arbitrary Git transports or remotes.
Interrupted replacement must not leave a partially updated managed payload
presented as healthy.

## Decision

- `lib/vendor-inventory.sh` owns the typed filesystem inventory: directories,
  regular-file content and executable state, and exact symbolic-link targets.
- POSIX `cksum` is retained as a portable accidental-change detector in a
  trusted local workspace. It is not an authenticity proof or tamper seal.
- `lib/vendor-provenance.sh` validates stored provenance and permits remote
  staleness queries only through the canonical credential-free HTTPS source.
- Staleness compares the managed skill payload rather than whole-repository
  commits.
- `lib/vendor-transaction.sh` stages and verifies a complete replacement on
  the destination filesystem before activation, with durable recovery state
  outside the managed payload.
- Destination containers and the `AGENTS.md` pointer must be real local
  filesystem entries, not symlinks that can redirect writes outside the
  selected project.
- `vendor.sh --check` remains read-only. Mutating modes validate destination
  safety and committed source state before starting a transaction.

## Consequences

Vendored copies can be checked, refreshed, and recovered with explicit failure
states instead of partial success. Local edit detection is portable but does
not defend against a deliberate checksum collision or a maliciously replaced
manifest. Environments requiring adversarial integrity need a trusted signed
release or manifest, which remains outside this repository's supported threat
model.
