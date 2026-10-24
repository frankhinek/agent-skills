---
summary: "Keep agent instructions and retained source copies out of the live record inventory without hiding live validation records."
read_when:
  - Changing record discovery or reference-scan boundaries
  - Configuring linter exclusions for archived source trees
title: "Lint Corpus Boundary"
---

# Lint Corpus Boundary

Date: 2026-10-24
Status: Accepted

## Context

Agent instructions can share a `specs/` directory with records. Retained source
snapshots can contain copies of record IDs that remain live elsewhere. Treating
either as additional live records creates false findings; excluding every
validation directory would also hide legitimate records and references.

## Decision

Exclude `AGENTS.md` and `CLAUDE.md` from the record inventory while retaining
their references in the reference scan. Use the existing generated-directory
and nested-skill boundaries for both discovery and reference scans.

Allow a project-root `.assuranceignore` to name explicit, literal
directory exclusions. Require existing normalized project-relative paths with
no symlink components. Reject invalid configuration, report every exclusion,
and keep archived IDs out of the live reference target set.

## Consequences

Projects own the scope of their live corpus without changing retained evidence
or patching vendored code. A clean result applies only to that declared scope;
reviewers must check exclusion changes alongside the records they would hide.
