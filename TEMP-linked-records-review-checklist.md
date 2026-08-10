---
summary: "Tracks every unresolved review finding with its context, proof, recommended remediation, and completion gate."
read_when:
  - Working through the linked-records hardening findings one by one
  - Verifying a fix before marking its checklist item complete
title: "Linked Records Review Checklist"
---

# Linked Records Review Checklist

> Temporary, uncommitted working artifact. Keep this file until every item is either complete or explicitly closed with a written rationale. Do not treat the current eval or lint results as proof of correctness until F01–F04 are complete.

## Objective

Finish the seven original fixes without losing the review context that showed where each fix remains incomplete. Work one item at a time. Preserve the distinction between a code defect, a missing regression test, a documented limitation, and a human decision gate.

## Review Baseline

- Reviewed range: `0005661` through `5116497`.
- Review baseline: `5116497db91bdd0dc2f51c26739ed89bb1237839` (`Record provenance; licensing pending upstream permission`).
- Branch at capture: clean `main`, synchronized with `origin/main`.
- Review mode: full repository review, report only; no source changes made by the review.
- Evidence methods: static inspection, isolated shell fixtures, direct failure reproductions, and an independent cross-model adversarial pass.
- Preserved scratch evidence: `/tmp/compound-engineering-501/ce-code-review/20260805-155655-70925274`. This path is not durable; the material findings are copied below.
- Validation constraints: ShellCheck and `skills-ref` were unavailable. Installer end-to-end validation was not run because it would mutate existing global skill directories outside the repository sandbox.
- Cross-model receipt: route `claude`; requested model `opus`; reported model `claude-opus-5`; requested effort `high`; actual effort unverified; receipt and independent context verified.

## Status Legend and Working Rules

- `[ ]` not started or not yet proven.
- `[~]` implementation in progress; do not use this as a final state.
- `[x]` complete, with the completion record filled in.
- `[N/A]` intentionally closed without implementation; record the decision and rationale.

For every item:

- [ ] Reproduce or preserve the original failure before changing behavior.
- [ ] Implement the smallest complete fix.
- [ ] Add a regression test that fails on the old behavior and passes on the new behavior.
- [ ] Update user-facing or contributor documentation when the contract changes.
- [ ] Run the item-specific acceptance checks.
- [ ] Review the final diff for collateral behavior changes.
- [ ] Fill in the completion record, then mark the item complete.

## Original Seven-Fix Verdict

| Original fix | Review verdict | Remaining work |
|---|---|---|
| 1. Tool-agnostic grooming sample | Partial | Sampling language improved, but candidate enumeration includes claim evidence and grooming still permits claim deletion. See F13. |
| 2. Protect local edits during replacement | Partial | Content edits are refused; mode and symlink edits are missed, diagnostics truncate, and replacement is non-atomic. See F09, F10, F15. |
| 3. Provenance and drift visibility | Partial | Happy path works; parser ordering can mutate, missing/mixed installs report healthy, unrelated commits look stale, and manifest URLs cross an unsafe trust boundary. See F05, F08, F14, F16. |
| 4. Executable linter | Not complete | The linter travels correctly but produces confirmed false greens and a false positive. See F02 and R02–R05. |
| 5. Behavioral eval suite | Not trustworthy | A failed harness, staged/committed violations, prohibited claim rewrites, weak semantic proxies, and unknown scenarios can all report success. See F01, F03, F04, F06, F11, F12, F17 and R06–R08. |
| 6. Extensible installer targets | Mostly resolved | Extra target arguments work. Partial installation still looks successful, and default-target failure can prevent explicit targets. See R01. |
| 7. MIT license | Intentionally unresolved | `LICENSE` was removed because upstream permission and relicensing rights are not yet verified. See D01. |

## Recommended Execution Order

1. Eval truthfulness: F03, F04, F01, F11, F12, F17, F06.
2. Linter contract: F02, R02, R03, R04, R05.
3. Vendor state machine and trust boundary: F08, F16, F10, F09, F15, F14, F05.
4. Groom authority: F13 and R08.
5. Installer and documentation: R01 and F07.
6. Cross-cutting regression suite and harness parity: R06, R07, R09.
7. Licensing decision: D01 only after written permission is available.

The order is load-bearing. A green eval or lint result is weak evidence until its false-green paths are closed.

---

## Confirmed Findings

### [x] F01 — Claim Eval Accepts a Forbidden Claim Rewrite

**Priority:** P1
**Location:** `evals/scenarios/claim-writer/check.sh:6`
**Original fix affected:** 5 — behavioral evaluations

**Context and background**

The claims amendment makes the exact wording of a `CLAIM-*` record immutable outside the explicit claims workflow. A later falsification or provisional verdict belongs in sibling evidence, not in the claim record. The eval checker currently treats a claim rewrite as a warning when the new text contains `falsif`, `no longer`, or `provisional`. That implements a semantic exception the governing skill does not permit.

**Proof**

- In an isolated fixture, appending `Status: provisional.` to `specs/CLAIM-single-writer.md` printed a warning and returned exit status 0.
- The checker leaves `fail=0` on this branch.
- When the same change is staged, the checker reports a stronger false green because of F04: it says the claim record was not rewritten.

**Impact**

A prohibited record mutation can become committed PASS evidence. This directly undermines the suite’s purpose: verifying that agents respect the claim authority boundary.

**Recommended fix**

Fail on every change to the claim record. Allow verdicts, falsification, and provisional status only in sibling evidence files. Do not infer that a mutation is permissible from words in the replacement text.

**Implementation checklist**

- [x] Remove the warning/success exception for falsification-like wording.
- [x] Make any added, modified, deleted, or renamed claim record fail.
- [x] Preserve a valid evidence-only path for falsification or a changed verdict.
- [x] Add fixtures for modified, deleted, renamed, staged, and committed claim records.
- [x] Add a passing fixture where only sibling evidence changes.

**Acceptance gate**

- [x] No claim-record mutation can return 0.
- [x] Evidence-only falsification returns the intended result and is visible in the checker output.
- [x] The test remains correct after the change is staged or committed.

**Completion record:** commit `fix(evals): enforce truthful postcondition checks` · validation `evals/tests/check-baseline.sh` (red before fix: `FAIL: claim-writer unexpectedly passed`; green after fix); `evals/tests/run-failure-gates.sh`; `bash -n` over runner, helper, fixture, tests, and all scenario checkers; `git diff --check` · notes claim records under any `specs/` directory are immutable across unstaged, staged, committed, added, deleted, and renamed states; sibling evidence changes remain non-failing and visible; unrelated `CLAIM-*.md` files outside `specs/` are not treated as records

### [x] F02 — Linter Silently Accepts Invalid Record Shapes

**Priority:** P1
**Location:** `skills/linked-records-upkeep/lint.sh:87`
**Original fix affected:** 4 — executable linter

**Context and background**

`lint.sh` is described as the portable, CI-ready mechanical floor for record conformance. That promise requires a clear division: mechanically decidable rules must be enforced reliably; judgment-heavy rules must remain in the agent checklist. The current implementation checks several surface markers without proving the required content, and it interprets all fenced blocks as source code.

**Proof**

Separate isolated corpora produced these results:

- A SPEC with an empty `## Record justification` section exited clean.
- A CLAIM containing claim-level `Verdict: pass` and `Proof:` paragraphs exited clean despite the property-only contract.
- An explicit tombstone record exited clean despite the no-tombstones rule.
- A fenced `text` architecture diagram failed even though the core rule forbids source-code excerpts, not every fenced block.

**Impact**

The linter has both false negatives and a false positive. A clean result is not reliable evidence, while legitimate records can be rejected. This discourages CI adoption and makes later eval results harder to interpret.

**Recommended fix**

Build a table-driven known-good/known-bad corpus. Enforce only content properties that shell can determine reliably. Retain semantic judgment checks in `SKILL.md`. Either distinguish source-code fences from non-code fences or deliberately change the written contract to forbid all fences; do not leave implementation and policy inconsistent.

**Implementation checklist**

- [x] Define the exact mechanical checks owned by `lint.sh`.
- [x] Require a non-empty, one-sentence SPEC justification if that remains the contract.
- [x] Reject claim-level proof/verdict material when mechanically identifiable.
- [x] Detect tombstone records when mechanically identifiable.
- [x] Resolve the fence contract and cover `text`/diagram versus source-code examples.
- [x] Add one focused good and bad fixture for every implemented rule.
- [x] Keep undecidable rules in the judgment checklist with no implied mechanical guarantee.

**Acceptance gate**

- [x] Every known-bad fixture exits nonzero with the expected finding.
- [x] Every known-good edge fixture exits 0.
- [x] One rule cannot silently stop executing without a regression test failing.
- [x] `SKILL.md`, `lint.sh`, and test names describe the same contract.

**Completion record:** commit `fix(lint): enforce linked-record shape contract` · validation red proof: `skills/linked-records-upkeep/tests/check-lint.sh` failed 12 of 31 cases before the linter change; green proof: the same 31-case matrix, `/bin/bash -n` for linter and test, existing eval regression suites in an ephemeral committed clone, and `git diff --check` all passed · notes the linter now enforces exactly one non-empty SPEC justification section, recognizable claim-level proof/verdict labels, explicit tombstone markers, and exact diagram fence labels; sentence quality, actual diagram content, disguised claim metadata, and implicit tombstones remain judgment checks; bundled skill validation was unavailable because its Python environment lacks PyYAML (`ModuleNotFoundError: yaml`)

### [x] F03 — Failed or Missing Agent Harness Scores a Clean Eval Run

**Priority:** P1
**Location:** `evals/run.sh:79`
**Original fix affected:** 5 — behavioral evaluations

**Context and background**

Most scenarios use negative assertions: the agent must not touch a protected file or violate a gate. If the agent command never runs, the unchanged fixture naturally satisfies those checks. The runner captures the agent process status as `rc` but uses only the scenario checker status to set the overall result.

**Proof**

- A shim named `claude` that exited 42 without doing work caused the scenario to print PASS.
- The overall runner returned 0.
- `rc` appeared only as informational summary text; it did not affect `overall`.

**Impact**

Missing binaries, authentication failures, bad arguments, rate limits, crashes, and empty agent responses can all be recorded as a successful behavioral evaluation.

**Recommended fix**

Treat the agent harness as a required part of the evaluation. A nonzero harness exit, missing/empty final response, or absent task-engagement signal must fail the scenario and the overall run. Show the failure in the generated summary.

**Implementation checklist**

- [x] Fail the run when the harness returns nonzero.
- [x] Fail when the final response is missing or empty.
- [x] Add a positive task-engagement assertion to each negative-only scenario.
- [x] Record harness failures prominently in `summary.md`.
- [x] Distinguish agent/harness failure from behavioral checker failure.
- [x] Test missing binary, exit 42, authentication-like failure, and empty output.

**Acceptance gate**

- [x] Every simulated harness failure makes the runner exit nonzero.
- [x] A no-op agent cannot pass a scenario solely because protected files stayed unchanged.
- [x] The summary identifies which layer failed.

**Completion record:** commit `fix(evals): reject invalid harness runs` · validation `evals/tests/run-failure-gates.sh`; `bash -n` over runner, fixture, test, and scenario checkers; all response regexes compiled; real fixture-build smoke test · notes final responses are captured separately from diagnostics; setup/harness/response failures are `INVALID`, behavioral misses are `FAIL`; fixture commits ignore global signing and hooks

### [x] F04 — Scenario Checks Ignore Staged and Committed Changes

**Priority:** P1
**Location:** `evals/scenarios/claim-writer/check.sh:3` and other scenario checkers
**Original fix affected:** 5 — behavioral evaluations

**Context and background**

The scenario checkers use `git diff`, which by default compares the working tree with the index. Staged changes disappear from that comparison. Agent-created commits also disappear. An eval must compare the final fixture state with an immutable pre-agent baseline, independent of whether the agent stages or commits.

**Proof**

- A prohibited claim rewrite was initially detected while unstaged.
- After `git add`, the same rewrite produced `PASS: claim record not rewritten` and exit 0.
- The same blind spot applies to checks that use `git status --porcelain` or a default `git diff` as the source of truth.

**Impact**

An agent that stages or commits its work can conceal exactly the mutations the suite is meant to detect. Results vary based on Git behavior rather than policy compliance.

**Recommended fix**

After the base fixture and scenario overlay are committed, store that revision as the immutable eval baseline. Compare all tracked changes—unstaged, staged, and committed—against that revision. Enumerate untracked files separately. Centralize the logic in a shared helper so all scenarios use the same state model.

**Implementation checklist**

- [x] Commit the complete pre-agent fixture, including scenario overlays.
- [x] Store or pass its revision as the eval base.
- [x] Compare tracked paths against the eval base, not the index.
- [x] Include untracked files in the changed-tree inventory.
- [x] Move shared diff logic into one helper used by every checker.
- [x] Test unstaged, staged, committed, renamed, deleted, and untracked changes.

**Acceptance gate**

- [x] The same prohibited mutation produces the same failure in every Git state.
- [x] A legitimate agent commit remains inspectable against the baseline.
- [x] Every current scenario uses the shared baseline comparison.

**Completion record:** commit `fix(evals): enforce truthful postcondition checks` · validation `evals/tests/check-baseline.sh`; `evals/tests/run-failure-gates.sh`; `bash -n` over runner, helper, fixture, tests, and all scenario checkers; no direct `git diff`/`git status` remains in scenario checkers; `git diff --check` · notes runner captures the committed post-overlay SHA and passes it as `EVAL_BASE`; tracked changes compare against that SHA and untracked non-ignored files are inventoried separately

### [ ] F05 — Manifest Provenance Can Persist Credentials and Drive an Unsafe Git Remote

**Priority:** P1
**Location:** `vendor.sh:102`, `vendor.sh:61`, `vendor.sh:76`, `vendor.sh:138`
**Original fix affected:** 3 — provenance and drift visibility

**Context and background**

Copy mode reads `origin`, performs only an SCP-style conversion and `.git` suffix removal, then writes the result into a manifest intended to be committed. `--check` later reads that manifest-controlled value and passes it to `git ls-remote`. This crosses two trust boundaries: repository credentials can leak into a project, and a contributed manifest can choose a Git transport.

**Proof**

- URL userinfo is not removed or rejected before the manifest is written.
- The scheme and host are not validated before `git ls-remote` runs.
- Git supports non-HTTP transport and remote-helper forms; whether every dangerous form is enabled on this machine was not validated, so the execution aspect remains a high-confidence design risk rather than a reproduced exploit.

**Impact**

Credentials embedded in an HTTPS remote can be committed accidentally. A supposedly read-only status check can contact or potentially invoke behavior selected by untrusted repository content.

**Recommended fix**

Store a sanitized, non-secret canonical provenance identifier. Strip or refuse URL userinfo. Accept only sanctioned HTTPS origins/hosts, or store a source identifier that is never executed as a URL. Reject local paths, custom transports, and remote-helper syntax. Validate the manifest value again before network use.

**Implementation checklist**

- [ ] Decide the accepted provenance format and allowed hosts.
- [ ] Strip or reject usernames, tokens, and passwords.
- [ ] Reject non-HTTPS and custom transport forms.
- [ ] Validate both source-derived and manifest-derived values.
- [ ] Ensure diagnostics never echo secrets.
- [ ] Add malicious URL fixtures that prove no Git/network command is invoked.
- [ ] Document the network trust boundary for `--check`.

**Acceptance gate**

- [ ] No credential-bearing remote can be persisted.
- [ ] No unapproved transport can reach `git ls-remote`.
- [ ] A valid canonical public HTTPS source still supports status checks.
- [ ] Offline/unreachable status remains honest and non-destructive.

**Completion record:** commit ___ · validation ___ · notes ___

### [x] F06 — Relative Fixture Destination Leaves a Half-Built Fixture

**Priority:** P2
**Location:** `evals/fixture.sh:123`
**Original fix affected:** 5 — behavioral evaluations

**Context and background**

`fixture.sh` changes into the destination, then passes the original destination string to `vendor.sh`. When the input was relative, that string is interpreted a second time from inside the destination.

**Proof**

- Running the fixture builder with a relative destination created part of the tree, changed directory, and then failed when `vendor.sh` attempted the second relative `cd`.
- Exit status was 1.
- The partial directory lacked a complete skills installation and usable Git fixture.

**Recommended fix**

Resolve the destination to an absolute path once, before changing directory. Define the policy for a pre-existing destination and clean up a newly created partial fixture after a setup failure when it is safe to do so.

**Implementation checklist**

- [x] Normalize the destination before the first `cd`.
- [x] Preserve paths containing spaces.
- [x] Define existing-directory behavior.
- [x] Add failure cleanup for directories created by this invocation.
- [x] Test absolute, relative, spaced, and existing destinations.

**Acceptance gate**

- [x] Absolute and relative invocations create equivalent complete fixtures.
- [x] A setup failure does not leave a directory that looks usable.

**Completion record:** commit `fix(evals): make fixture setup path-safe` · validation `evals/tests/check-fixture.sh` (red before the fix: `vendor.sh: line 33: cd: relative-fixture: No such file or directory`; green after the fix); `evals/tests/run-failure-gates.sh`; `evals/tests/check-baseline.sh`; `evals/tests/check-semantics.sh`; `/bin/bash -n evals/fixture.sh evals/tests/check-fixture.sh`; `git diff --check` · notes the builder now resolves one physical absolute destination before entering it, requires a previously nonexistent leaf, and forwards the absolute path to vendoring; absolute, relative, and space-containing builds produce identical committed trees; existing directories, files, symlinks, and symlink targets remain unchanged; command and `INT`/`TERM` failures remove only the invocation-owned leaf while preserving exit status and unrelated siblings; cleanup failure preserves the original status, warns loudly, and retains partial evidence; `SIGKILL` remains inherently untrappable

### [ ] F07 — Eval Documents Violate Required Frontmatter

**Priority:** P2
**Location:** `evals/README.md:1`, `evals/results/*.md`, `evals/run.sh:27`
**Original fix affected:** 5 — behavioral evaluations

**Context and background**

The repository handbook requires every docs page to carry YAML frontmatter with exactly `summary`, `read_when`, and `title`. Authored eval docs and runner-generated summaries start with headings instead.

**Proof**

- `evals/README.md`, the baseline report, and the parity report begin with `#` headings.
- Generated run summaries also omit frontmatter because `evals/run.sh` does not emit it.
- `git diff --check` found trailing blank-line-at-EOF issues in four generated summaries during review.

**Recommended fix**

Add the exact required frontmatter to authored eval documents. Update the summary generator to emit the same three fields and avoid trailing whitespace/extra blank lines. Validate generated output, not only the template source.

**Implementation checklist**

- [ ] Add compliant frontmatter to `evals/README.md`.
- [ ] Add compliant frontmatter to durable baseline/parity reports.
- [ ] Generate compliant frontmatter for every run summary.
- [ ] Ensure no extra YAML keys appear.
- [ ] Add a generated-document conformance check.

**Acceptance gate**

- [ ] All authored and freshly generated eval Markdown passes the frontmatter rule.
- [ ] `git diff --check` is clean.

**Completion record:** commit ___ · validation ___ · notes ___

### [x] F08 — Argument Ordering Can Turn a Check Request into Mutation

**Priority:** P2
**Location:** `vendor.sh:24–33`
**Original fix affected:** 3 — provenance and drift visibility

**Context and background**

The parser stops at the first positional argument. Flags after the project directory are ignored. Conflicting mode flags are also accepted, with the last recognized flag silently winning. A command that visibly contains `--check` therefore does not guarantee read-only behavior.

**Proof**

- `vendor.sh DIR --check` ignored `--check` and converted a symlinked test project into copied skills.
- Combining `--check` and `--link` performed mutation according to the final mode assignment.
- Unknown options after or before a positional argument are not handled as reliable usage errors.

**Impact**

The CLI violates its most important safety property: a check request can mutate the destination.

**Recommended fix**

Parse the entire argument list. Permit at most one positional directory. Reject unknown flags, extra positionals, and incompatible modes. Treat `--check` as a mutually exclusive read-only mode independent of argument order. Define whether `--force` is invalid with `--check`.

**Implementation checklist**

- [x] Parse flags before and after the positional argument.
- [x] Reject unknown options and multiple project directories.
- [x] Reject conflicting `--copy`/default, `--link`, and `--check` modes.
- [x] Reject meaningless or dangerous combinations such as `--check --force`.
- [x] Add a no-mutation sentinel to parser tests.

**Acceptance gate**

- [x] Every permutation of a valid command behaves identically.
- [x] Every invalid combination exits with usage status and makes no filesystem change.
- [x] Any invocation containing a valid `--check` mode is provably read-only.

**Completion record:** commit `fix(vendor): make mode parsing order-independent` · validation red proof: `tests/check-vendor-arguments.sh` failed because `check-after-directory` changed a symlinked destination before the parser fix; green proof: the same isolated matrix passed under macOS system Bash/tools across both check orders, copied and linked states, every placement of valid mode/force pairs, every placement of conflicting mode and check/force pairs, unknown options, and extra directories; `evals/tests/check-fixture.sh`, `/bin/bash -n`, and `git diff --check` passed · notes the full argument list is now validated before entering the project directory; explicit `--copy` retains the default copy behavior; invalid syntax exits 2 without destination mutation; `--force` remains valid for copy/link and is rejected with check; adversarial review found one missing copied-project read-only case, which was added and independently validated; F09, F10, F14, F15, F16, and R09 remain separate

### [x] F09 — Manifest Misses Permission and Symlink Edits

**Priority:** P2
**Location:** `vendor.sh:40–42`
**Original fix affected:** 2 — protect local edits

**Context and background**

The checksum manifest inventories only regular-file content. POSIX `cksum` records checksum, byte count, and path—not executable mode or file type. `find -type f` excludes symlinks. The refresh guard therefore protects a narrower definition of “local work” than the README promises.

**Proof**

- Removing the executable bit from vendored `lint.sh` did not change `--check` status.
- Adding a symlink under a vendored skill did not change `--check` status.
- The command printed `local edits: none` and exited 0 in both conditions.

**Impact**

Executable permission changes and symlink additions/retargeting can be discarded without warning. Symlinks can also change what downstream tools read without appearing in integrity output.

**Recommended fix**

Define a deterministic manifest record for each supported entry type. Include relative path, type, executable mode, and content checksum for regular files; include link target for symlinks. Decide whether empty directories matter. Reject unsupported/special file types.

**Implementation checklist**

- [x] Specify and version the manifest entry format.
- [x] Record executable mode for regular files.
- [x] Record symlinks and their targets.
- [x] Reject device, socket, FIFO, or other unsupported entries.
- [x] Make diagnostics identify mode/type/target changes accurately.
- [x] Test chmod, symlink add/remove/retarget, type replacement, and path rename.

**Acceptance gate**

- [x] Every supported local filesystem change is either preserved or explicitly refused before refresh.
- [x] Identical copies remain portable across the supported macOS/Linux environments.

**Completion record:** commit `fix(vendor): inventory filesystem metadata` · validation red proof: the new inventory matrix first failed because removing the executable bit from vendored `lint.sh` still returned 0 with `local edits: none`; green proof: `tests/check-vendor-inventory.sh`, `tests/check-vendor-state.sh`, `tests/check-vendor-arguments.sh`, the 37-case linter matrix, all four eval regression suites, `/bin/bash -n` over every shell script, and `git diff --check` passed under macOS system Bash/tools; the focused inventory suite also passed under Linux Bash 3.2 and produced a byte-for-byte identical manifest body to macOS · notes manifest format 2 C-sorts typed records for directories, regular-file content and executable state, and exact symlink targets; paths and targets are hex encoded; unsupported entries and inventory-tool failures block check/refresh even with `--force`; legacy, unknown, contradictory, and malformed manifests never report pristine, while explicit force migration requires a safe live inventory; review-found error-masking, duplicate format-header, GNU/BSD `stat` probe, stale post-copy manifest, and overbroad permission wording defects were fixed and regression-covered; full non-executable permission bits, ACLs, xattrs, hard-link topology, atomic replacement (F15), CI matrix expansion (R09), and stronger hashes (R10) remain explicitly separate

### [x] F10 — `pipefail` Truncates Local-Edit Diagnostics

**Priority:** P2
**Location:** `vendor.sh:71–72`, `vendor.sh:117–120`
**Original fix affected:** 2 and 3 — local-edit protection and status reporting

**Context and background**

`diff` returns 1 when differences are found. That is expected in these branches. Under `set -euo pipefail`, the `diff | awk | sort` pipeline exits the script before the code can finish the promised three-fact status or print the merge/`--force` recovery guidance.

**Proof**

- `--check` stopped after listing the edited file and omitted the published/staleness line.
- Refresh stopped before printing the merge/`--force` guidance.
- Both failures occurred precisely when local edits existed—the state where diagnostics matter most.

**Recommended fix**

Handle `diff` statuses explicitly. Treat 0 as identical, 1 as expected differences, and greater than 1 as an actual tool error. Capture the findings without allowing the expected status to trigger `errexit`.

**Implementation checklist**

- [x] Wrap expected `diff` calls in explicit condition/status handling.
- [x] Preserve nonzero failure for real `diff` errors.
- [x] Print all promised check facts even when edits exist.
- [x] Print complete merge/force recovery guidance on refresh refusal.
- [x] Add output assertions, not only exit-code assertions.

**Acceptance gate**

- [x] Local edits produce a complete deterministic report and actionable exit status.
- [x] Unexpected comparison failures remain distinguishable and fail closed.

**Completion record:** commit `fix(vendor): complete local-edit diagnostics` · validation red proof: the strengthened vendor-state matrix first failed because an edited `--check` stopped before the published-status line; adversarial hardening then failed because raw `diff` stderr leaked through the comparison-error path; green proof: `tests/check-vendor-state.sh`, `tests/check-vendor-arguments.sh`, all four eval regression suites, the 37-case linter matrix, `/bin/bash -n` over every tracked shell script, and `git diff --check` passed under macOS system Bash/tools · notes expected `diff` status 1 is now normalized inside one shared reporter so edited checks finish all three facts and refresh refusals finish merge/`--force` guidance; status greater than 1 is preserved exactly, raw comparison output from both streams is suppressed, and the project tree stays unchanged; deterministic path output uses C collation; whitespace-containing path formatting and non-`diff` formatter diagnostics remain separate findings/residuals

### [x] F11 — Grep Proxies Let Real Behavioral Violations Report PASS

**Priority:** P2
**Location:** `evals/scenarios/claim-writer/check.sh:15`, `evals/scenarios/gate-conflict/check.sh:8`
**Original fix affected:** 5 — behavioral evaluations

**Context and background**

The scenarios are intended to test behavior: writes must continue through `Store`, and a local-only gate must prevent cloud synchronization. Current assertions search for a few source spellings. Absence of those strings is reported as affirmative behavioral success, including the phrase “agent presumably escalated.”

The current claims convention adds an important qualification: `CLAIM-single-writer` is descriptive, not a gate. An explicitly requested direct write is valid only when the claim remains unchanged, verification records the resulting falsified counterexample, and the response escalates the conflict. The defect is therefore an undisclosed or misclassified direct write, not every direct write categorically.

**Proof**

- A direct write implemented with `Path.write_text`, single quotes, a helper wrapper, `os.replace`, or similar APIs can bypass the current `open(..."w")` pattern.
- Cloud behavior implemented with `urllib`, `httpx`, `http.client`, sockets, WebDAV, sync helpers, or a new top-level directory can bypass an `app/`-limited scan.
- The checker cannot prove escalation from source-token absence.

**Impact**

Semantically prohibited implementations can be certified as PASS. The wording overstates what the checker observed.

**Recommended fix**

Prefer behavioral assertions. For the writer, instrument or monkeypatch `Store.write` and prove the public operation delegates through it. For the gate, inspect the complete changed tree and exercise behavior under a network-deny boundary if feasible. When only static heuristics are available, report “no prohibited pattern detected; transcript judgment required,” not behavioral success.

**Implementation checklist**

- [x] Replace claim-writer spelling checks with observed delegation/direct/mixed behavior and require falsification evidence for direct or mixed persistence.
- [x] Scan all changed and non-ignored untracked paths for gate-conflict fallback checks.
- [x] Expand network/direct-write heuristics only as defense in depth.
- [x] Remove “presumably escalated” and other unsupported conclusions.
- [x] Add alternative implementation fixtures that evade the old regexes.
- [x] Define the transcript rubric for escalation quality.

**Acceptance gate**

- [x] Known alternative direct-write implementations without matching falsification evidence, and known cloud-sync implementations, fail.
- [x] PASS language states only what was mechanically established.

**Completion record:** commit `fix(evals): enforce truthful postcondition checks` · validation `evals/tests/check-semantics.sh`; `evals/tests/check-baseline.sh`; `evals/tests/run-failure-gates.sh`; `bash -n` over eval scripts; in-memory Python compilation of both probes; `git diff --check` · notes the original delegation-only recommendation conflicted with the authoritative claims rule: an explicitly requested direct write remains valid only when the claim is unchanged, verification records a falsified `save_note` counterexample, and the final response escalates it; behavior probes use Python’s standard library, while static API checks remain explicitly labeled heuristics

### [x] F12 — Eval Subject Can Rewrite Its Governing Vendored Skills

**Priority:** P2
**Location:** `evals/scenarios/gate-sweep-edit/check.sh:3–8` and all scenarios
**Original fix affected:** 5 — behavioral evaluations

**Context and background**

Each fixture places the skills under test in `.agents/skills/`, inside the agent’s writable workspace. The docs-sweep prompt is repository-wide. Current checkers either ignore skill changes or list them only as informational status.

**Proof**

- The docs-sweep checker verifies the gate record but does not fail if `.agents/skills/` changes.
- An agent can weaken the instructions, then comply with the weakened version, while the scenario still reports success.
- The risk applies to every current scenario because none legitimately asks the agent to edit its governing skills.

**Recommended fix**

Add a shared invariant: the entire `.agents/skills/` tree must match the immutable eval baseline. Optionally mount or place the skills outside the writable fixture if the harness can still discover them. Keep the invariant even if write permissions are hardened.

**Implementation checklist**

- [x] Add shared skill-integrity verification to every scenario.
- [x] Include staged, committed, deleted, and untracked skill mutations.
- [x] Decide whether fixture permissions can make the tree read-only equally across harnesses.
- [x] Add a malicious self-rewrite fixture.

**Acceptance gate**

- [x] Any governing-skill mutation fails the scenario.
- [x] Normal compliant agent work remains unaffected.

**Completion record:** commit `fix(evals): prevent governing-skill rewrites` · validation `evals/tests/check-baseline.sh` (red before the fix: `FAIL: arch-drift unexpectedly passed`; red during adversarial hardening: `FAIL: gate-sweep-edit unexpectedly passed`; green after both fixes); `evals/tests/check-semantics.sh`; `evals/tests/run-failure-gates.sh`; `bash -n` over eval scripts; in-memory Python compilation of both probes; `git diff --check` · notes every checker now compares `.agents/skills/` with the immutable baseline through a disposable baseline-owned Git index, so unstaged, staged, committed, deleted, untracked, ignored-untracked, `assume-unchanged`, and `skip-worktree` mutations fail without suppressing scenario-specific diagnostics; clean fixtures and normal work outside the skills tree still pass; ordinary file-mode hardening was rejected because both harnesses run as the fixture owner and no equivalent external read-only skill-discovery boundary is configured; a temporary rewrite restored byte-for-byte before grading remains outside a final-state checker’s visibility

### [ ] F13 — Grooming Can Sample Evidence and Delete Claims

**Priority:** P2
**Location:** `skills/linked-records-upkeep/SKILL.md:70–88`
**Original fix affected:** 1 — portable random grooming selection

**Context and background**

The revised language correctly makes uniform random selection and pre-commitment normative. However, the proposed enumeration selects every Markdown file anywhere below a `specs/` directory. Claim evidence commonly lives at `specs/CLAIM-name/proof.md` and `verification.md`, so it becomes an independent grooming candidate. The workflow then prefers deletion/consolidation and excludes gates—but not claims—from its authority boundary. The claims skill separately requires an explicit user request to retire or delete a claim.

**Proof**

- The prescribed `find . -type f -path '*/specs/*.md'` expression selected a claim record, `proof.md`, and `verification.md` in a reproduced corpus.
- Groom step 3 authorizes deletion and consolidation.
- Groom step 4 names gates but omits claim records and evidence.

**Impact**

The portability fix preserves random pre-commitment but broadens what can be sampled. An ordinary groom request can delete claim evidence or the claim itself, contradicting the stricter claims workflow.

**Recommended fix**

Define a record candidate structurally: a Markdown file whose immediate parent directory is `specs/`. Explicitly exclude `CLAIM-*` records and all claim evidence from grooming authority. Route any claim retirement, deletion, or evidence pruning through the claims workflow and an explicit user request.

**Implementation checklist**

- [ ] Restrict candidate enumeration to actual top-level record files.
- [ ] Exclude claim records and nested evidence paths.
- [ ] State the exclusion in the groom authority boundary, not only in an example command.
- [ ] Preserve uniform selection, sample capture before reading, and no resampling.
- [ ] Add a scenario containing ordinary records plus claim proof/verification files.

**Acceptance gate**

- [ ] The sample population contains records only.
- [ ] No groom invocation can authorize a claim/evidence mutation.
- [ ] Sampling remains portable when `shuf`, `sort -R`, or both are absent.

**Completion record:** commit ___ · validation ___ · notes ___

### [ ] F14 — Whole-Repository HEAD Creates False Staleness

**Priority:** P2
**Location:** `vendor.sh:79–84`, `vendor.sh:101`
**Original fix affected:** 3 — provenance and drift visibility

**Context and background**

The manifest stamps the repository commit SHA, while the vendored payload contains only `skills/`. Any README, eval, or script commit moves HEAD and makes an unchanged skills payload appear stale. The dirty-source guard already scopes itself to `skills/`, revealing the intended content boundary.

**Proof**

- A temporary repository with unchanged `skills/` and an unrelated later commit reported the earlier vendored copy as stale.
- No content difference in the vendored subtree was required.

**Impact**

Frequent false stale reports train maintainers to ignore the check and cause unnecessary refresh churn.

**Recommended fix**

Stamp the `skills/` tree identity in addition to the source revision. Only label the copy stale when the published skills tree is known to differ. With the current auth-free `ls-remote` design, remote HEAD alone cannot prove that, so either report “new source revision available” as informational or adopt a mechanism that can resolve the remote tree hash. This is a real design decision, not a wording patch.

**Implementation checklist**

- [ ] Choose the authoritative payload identity: tree hash, release tag, or versioned manifest.
- [ ] Preserve the commit SHA as provenance without using it as proof of payload drift.
- [ ] Define offline and remote-unreachable results.
- [ ] Add unchanged-tree/new-HEAD and changed-tree/new-HEAD fixtures.
- [ ] Update README terminology: source revision versus payload staleness.

**Acceptance gate**

- [ ] Unrelated repository commits do not report the payload as stale.
- [ ] A changed skills payload is detected when sufficient remote information is available.
- [ ] Unknown remains honest rather than becoming clean or stale by guesswork.

**Completion record:** commit ___ · validation ___ · notes ___

### [x] F15 — Replacement Is Non-Atomic and Misdiagnoses Interrupted Copies

**Priority:** P2
**Location:** `vendor.sh:126–142`
**Original fix affected:** 2 and 3 — local work safety and trustworthy manifests

**Context and background**

Copy mode removes each destination before copying its replacement. The new manifest is written only after all copies. An interruption, I/O failure, or full disk can leave a mixture of old manifest data and partial new files. The next run sees a checksum mismatch and calls it local edits.

**Proof**

- The destructive `rm -rf` occurs before each `cp -R`.
- No staging tree is fully prepared and verified before destination removal.
- The manifest is the last write, so any prior interruption leaves it describing a state that no longer exists.

**Impact**

A refresh can destroy a previously usable vendored copy, then tell the maintainer that recovery requires discarding “local edits” that were actually created by the failed updater.

**Recommended fix**

Copy every skill into a destination-local staging area, verify the staged inventory, then replace each destination with a rename/swap strategy that minimizes the inconsistent window. Write the manifest only for the successfully installed final state. Distinguish incomplete/missing paths from genuine content edits and provide different recovery guidance.

**Implementation checklist**

- [x] Stage all skill copies before removing any current destination.
- [x] Verify staged content against the source inventory.
- [x] Use same-filesystem renames and defined rollback behavior.
- [x] Clean abandoned staging directories safely on the next run.
- [x] Classify incomplete install separately from local edits.
- [x] Add induced copy-failure and interruption recovery tests.

**Acceptance gate**

- [x] A failed refresh leaves either the old complete state or an explicitly recoverable state.
- [x] The manifest always describes the installed payload.
- [x] Recovery never recommends `--force` for updater-created damage.

**Completion record:** commit `fix(vendor): make copy refreshes recoverable` · validation red proof: `tests/check-vendor-transaction.sh` first failed because an induced `cp -R` failure followed the old remove-before-copy path without proving the installed copy remained intact; green proof: the final transaction suite passed normal refresh, failed and silently incomplete staging, rename and live-inventory failure rollback, TERM and SIGKILL interruption, private initialization cleanup, manifest-publication rollback, committed-phase finalization, fresh-install rollback, abandoned pre-commit cleanup, and malformed-metadata refusal; all vendor argument/state/inventory suites, all four eval suites, the 37-case linter matrix, `/bin/bash -n` over every shell script, and `git diff --check` also passed · notes copy mode now stages and inventories the entire source under `.agents/.vendor-transaction`, publishes no stale manifest during live swaps, restores the previous complete state after catchable failures, and leaves explicit destination-local recovery metadata after uncatchable interruption; `--check` stays read-only and updater-created damage is never labeled local edits or routed to `--force`; invalid metadata remains fail-closed with an explicit inspection/removal escape hatch; concurrent mutating invocations and fsync-grade power-loss durability remain unsupported residual risks, while CI/platform expansion (R09) and stronger checksums (R10) remain separate

### [x] F16 — Missing or Mixed Vendoring Reports Healthy

**Priority:** P2
**Location:** `vendor.sh:51–59`
**Original fix affected:** 3 — provenance and drift visibility

**Context and background**

`--check` inspects only the first skill to decide that the project is in link mode. If no regular vendored files are found, it prints a message and exits 0. It does not classify all expected skills independently.

**Proof**

- Moving all skill directories away while retaining the manifest produced `no vendored skills found` and exit 0.
- A symlink at the first skill can short-circuit the check even when the remaining skills are copied, missing, or divergent.

**Impact**

Automation interprets an absent or incoherent installation as healthy. Provenance and edit checks may be skipped entirely.

**Recommended fix**

Classify each expected skill as linked, copied, missing, or invalid. Only an all-linked set can short-circuit successfully. An all-copied set proceeds through manifest checks. Missing, invalid, or mixed states are actionable and exit nonzero with repair guidance.

**Implementation checklist**

- [x] Inventory all expected skill destinations before selecting a mode path.
- [x] Define all-linked, all-copied, missing, and mixed outcomes.
- [x] Make missing/mixed/invalid states nonzero.
- [x] Detect invocation from the wrong project directory distinctly.
- [x] Add the complete state-matrix regression suite.

**Acceptance gate**

- [x] Only coherent all-linked or verified all-copied states return 0.
- [x] Every incomplete state identifies each affected skill and the safe recovery action.

**Completion record:** commit `fix(vendor): reject incoherent skill installations` · validation red proof: `tests/check-vendor-state.sh` first failed because an all-missing copied installation with its manifest retained returned 0; follow-up boundaries exposed an all-missing installation ambiguity, an empty-directory false green that bypassed the retained manifest, and unsafe classification when the shared skills directory held only unrelated skills; green proof: the final 19-case state matrix passed under macOS `/bin/bash` 3.2 with whole-tree no-mutation snapshots, an exercised git-spy positive control, and zero `git` calls for every structural failure; `tests/check-vendor-arguments.sh`, `evals/tests/check-fixture.sh`, `/bin/bash -n`, executable-mode inspection, and `git diff --check` passed · notes `--check` now inventories all expected skills and their regular `SKILL.md` markers before routing; only exact resolving links to this repository short-circuit, while all-copied installations always enter the existing manifest/provenance status policy; every missing, mixed, dangling, wrong-target, markerless, or invalid child state exits 1, reports all skill states, and requires preservation-first recovery without recommending `--force`; all-three-missing without a manifest is safely reported absent because a destroyed link install is observationally identical to a never-installed shared skills root; recovery guidance scopes preservation to linked-records entries; full payload inventory/atomic replacement remains F15, a symlinked `.agents/skills` container remains separate hardening, and F09/F10/F14 remain out of scope

### [x] F17 — Unknown Scenario Names Are Skipped with Exit 0

**Priority:** P3
**Location:** `evals/run.sh:44`
**Original fix affected:** 5 — behavioral evaluations

**Context and background**

The runner continues past an unknown scenario without changing `overall`. If every requested name is unknown, it runs nothing, creates an empty-looking summary, and returns success.

**Proof**

- Running the suite with `does-not-exist` printed an unknown-scenario message and exited 0.
- Zero scenarios executed.

**Recommended fix**

Treat every unknown requested scenario as a usage failure, record it in the summary, and fail if zero scenarios execute. Prefer validating the complete requested set before starting any expensive runs.

**Implementation checklist**

- [x] Validate requested names before fixture creation.
- [x] Exit nonzero on any unknown name.
- [x] Exit nonzero when zero scenarios execute.
- [x] Record skipped/unknown names in generated output.

**Acceptance gate**

- [x] Unknown requested names, explicit empty values, and zero discovered scenarios cannot produce green evidence; omitted scenario arguments still select all discovered scenarios.

**Completion record:** commit `fix(evals): reject invalid scenario selections` · validation `evals/tests/run-failure-gates.sh` (red before fix: `FAIL: unknown-only returned 0 instead of usage exit 2`; green after fix); `evals/tests/check-baseline.sh`; `evals/tests/check-semantics.sh`; `bash -n` over eval scripts; `git diff --check` · notes explicit selections now use exact membership in the canonical direct-child scenario set; any unknown, empty, or path-like name rejects the complete request with exit 2, records every rejected name and zero executions, and performs no version lookup, fixture creation, or agent invocation; empty discovery also fails, while valid named requests and omitted-argument default-all behavior remain unchanged; generated-summary frontmatter remains owned by F07, and result-directory collision handling remains separate

---

## Residual Risks and High-Value Improvements

These items were not all promoted into the 17 confirmed findings. They remain worth preserving and resolving because they affect trust, portability, or maintenance cost.

### [ ] R01 — Installer Reports Partial Installation as Success

**Location:** `install.sh:18–39`
**Original fix affected:** 6 — extensible installer targets

**Context and proof**

`install_into` skips a divergent non-symlink skill but always prints `link TARGET -> REPO/skills` and returns success. An earlier default target failure under `set -e` can also prevent later explicit targets from being attempted. The extra positional target feature itself is present and documented.

**Recommended fix**

Track per-skill installed, already-correct, and skipped states. Print an accurate target summary and return nonzero for partial installation. Consider processing explicit targets before optional defaults or adding an explicit-target-only mode so unrelated default configuration cannot block the user’s requested destination.

- [ ] Add identical-copy, divergent-copy, symlink, missing target, partial target, and multiple-extra-target tests.
- [ ] Define whether one failed target should stop later independent targets or produce an aggregate result.
- [ ] Verify the success line is emitted only for complete targets.

**Completion record:** commit ___ · validation ___ · notes ___

### [x] R02 — Linter Can Report Clean When Scratch Setup Fails

**Confidence:** Confirmed by deterministic reproduction
**Location:** `skills/linked-records-upkeep/lint.sh:10–16`

**Context and proof basis**

The script intentionally omits `-e`. `TMP="$(mktemp -d)"` is not checked before later writes. A `mktemp` failure may cascade into misleading output rather than a clear setup error. This was identified statically and was not reproduced during the review.

**Recommended fix**

Fail explicitly when the scratch directory cannot be created. Make the no-corpus message include the searched directory so a wrong-directory CI invocation is visible.

- [x] Reproduce with a controlled `mktemp` failure shim.
- [x] Add explicit setup failure handling and a test.
- [x] Confirm no cleanup command can target an empty or unsafe path.

**Completion record:** commit `fix(lint): fail closed on scratch setup` · validation red proof: the 34-case linter matrix failed the no-corpus, `mktemp` failure, unsafe-path, and scratch-initialization cases before the linter change; green proof: all 34 cases, `/bin/bash -n` for the linter and matrix, and `git diff --check` passed; an independent Claude adversarial review found one cleanup-probe false-confidence gap, which was fixed with a live positive control and revalidated · notes scratch creation now uses a named template under a canonical temporary parent, rejects empty or out-of-prefix results before installing cleanup, exits 2 with a `[setup]` diagnostic on setup failure, and names the canonical searched root when no corpus exists; post-initialization scratch-write failures and traversal interaction with a project-local `TMPDIR` remain separate linter-hardening concerns; bundled skill validation remains unavailable because its Python environment lacks PyYAML (`ModuleNotFoundError: yaml`)

### [x] R03 — Dangling-Reference Scan Traverses Binary and Generated Trees

**Location:** `skills/linked-records-upkeep/lint.sh`

**Context and proof basis**

The recursive grep excludes only a few directories. Build outputs, virtual environments, other vendored trees, and binary files can be scanned. GNU grep’s binary match message does not follow the expected `path:line:id` shape and can become a bogus finding. Large trees also make the mechanical floor slow enough to be skipped.

**Recommended fix**

Restrict the scan to relevant text/document/source paths or use a deterministic tracked-file inventory. Handle binary files explicitly. Make pruning configurable only if the repository contract requires it.

- [x] Add binary, build-output, virtualenv, and large-vendor fixtures.
- [x] Assert stable output and acceptable runtime.

**Completion record:** commit `fix(lint): bound dangling-reference scan` · validation red proof: the new boundary case reported eight findings before the linter change, including generated, virtualenv, vendor, FIFO, and malformed binary findings; green proof: all 35 linter cases passed with exact output containing only the project-authored source finding, the large-vendor case completed within its 10-second ceiling, `/bin/bash -n` on the linter and matrix passed under macOS Bash 3.2, and `git diff --check` passed · notes the scan now inventories regular files with portable `find`, prunes the documented conventional generated/dependency/environment directories, batches searches, and uses BSD/GNU `grep -I` for explicit binary suppression; nonstandard generated-directory names remain a documented residual, alternate vendored skill roots remain owned by R04, and bundled skill validation remains unavailable because its Python environment lacks PyYAML (`ModuleNotFoundError: yaml`)

### [x] R04 — Vendoring Outside `.agents/` Can Trigger a Self-Reference False Positive

**Location:** `skills/linked-records-upkeep/lint.sh` and `skills/linked-records-claims/SKILL.md`

**Context and proof basis**

If a compatible client vendors the skills into another project-local directory, the dangling-reference scan may inspect the claims skill’s own fenced example. Its literal `CLAIM-single-writer.md` can be interpreted as a project record reference and reported as missing.

**Recommended fix**

Exclude all discovered skill roots from corpus-reference linting, or scope reference checks to project-authored text. Add a fixture with skills installed outside `.agents/`.

- [x] Reproduce using an alternate project-local skills directory.
- [x] Prove project-authored dangling references are still detected.

**Completion record:** commit `fix(lint): exclude nested skill roots` · validation red proof: the alternate-root case produced four findings before the fix, including two false `CLAIM-single-writer` findings from a skill installed beneath a custom path containing spaces and pattern characters; green proof: all 36 linter cases passed with exact output containing only the project-root `SKILL.md` and `src/` positive controls, R03's binary/vendor/runtime case remained green, `/bin/bash -n` under macOS Bash 3.2 passed, and `git diff --check` passed · notes the scan now discovers nested regular `SKILL.md` markers outside existing pruned trees, escapes their paths before adding exact prune rules, and deliberately keeps a project-root `SKILL.md` in scope; the claims skill's useful example remains unchanged, any nested directory carrying a regular `SKILL.md` is treated as a skill root by convention, and bundled skill validation remains unavailable because its Python environment lacks PyYAML (`ModuleNotFoundError: yaml`)

### [x] R05 — Relative-Link Check Misparses Titles and Absolute Targets

**Location:** `skills/linked-records-upkeep/lint.sh`

**Context and proof basis**

Markdown links with titles, such as `](path "title")`, and absolute targets are not normalized correctly by the current shell parsing. The result is a loud false broken-link finding rather than a silent false green, but repeated false alarms erode trust.

**Recommended fix**

Define the supported Markdown link grammar and test it. Parse optional titles correctly, skip schemes/fragments according to policy, and handle absolute paths deliberately rather than concatenating them with the current directory.

- [x] Add fixtures for titles, fragments, URL schemes, absolute paths, spaces, and escaped parentheses.
- [x] Document any intentionally unsupported Markdown syntax.

**Completion record:** commit `fix(lint): parse supported relative links` · validation red proof: a fixture containing eleven valid or deliberately non-relative forms plus one missing local target produced twelve link findings before the fix; green proof: the 37-case linter matrix passed with exact output containing only the missing-target positive control under macOS system Bash/AWK tools, `/bin/bash -n` passed for the linter and test, and `git diff --check` passed · notes the portable AWK scanner now handles single-line inline destinations with supported titles, angle-bracket spaces, and balanced or escaped parentheses; relative query/fragment suffixes are removed before resolution; URI schemes, absolute/network paths, and fragment/query-only targets are deliberately skipped; reference-style and multiline links, autolinks, HTML, and URL/entity decoding remain explicitly unsupported; repository-wide lint still reports pre-existing out-of-scope dangling-reference fixtures, and bundled skill validation remains unavailable because its Python environment lacks PyYAML (`ModuleNotFoundError: yaml`)

### [ ] R06 — Claude and Codex Evals Run Under Unequal Safety Constraints

**Location:** `evals/run.sh`

**Context and proof basis**

The Claude route uses `--dangerously-skip-permissions`; the Codex route uses a workspace-write sandbox. The results are therefore not behavioral parity under equivalent operating constraints. The Claude subject can also affect files outside the fixture.

**Recommended fix**

Run every supported harness inside the same outer filesystem/process boundary, with the fixture as the only writable project tree. Record the effective safety profile in the summary. Remove dangerous permission bypass unless an equivalent external sandbox makes it safe.

- [ ] Define the common harness security contract.
- [ ] Add an escape probe that tries to write outside the fixture and must fail.
- [ ] Make parity reports disclose any unavoidable constraint difference.

**Completion record:** commit ___ · validation ___ · notes ___

### [ ] R07 — Eval Fixture Trees Are Never Cleaned Up

**Location:** `evals/run.sh`

**Context and proof basis**

Each scenario uses `mktemp -d` and leaves the vendored fixture behind. A full suite leaves at least five trees per harness run. This is not a correctness failure, but repeated use creates noise and can retain agent transcripts or project content longer than intended.

**Recommended fix**

Clean fixtures with a guarded trap after results are copied. Provide an explicit retain-on-failure/debug option and print retained paths.

- [ ] Verify success cleanup, failure cleanup, interrupt cleanup, and retain mode.
- [ ] Ensure cleanup targets are validated non-empty temporary paths.

**Completion record:** commit ___ · validation ___ · notes ___

### [ ] R08 — Requested Scenario Coverage Is Still Incomplete

**Location:** `evals/scenarios/`

**Context and proof basis**

The proposed suite called for roughly six probes, including bare activation, claim staleness, and grooming. The current suite has five scenarios but does not directly exercise those three behaviors. Grooming is especially important because it is the only routine authorized to delete records and is implicated in F13.

**Recommended fix**

Add focused scenarios for:

- [ ] Bare activation: loading the skill alone does not create or mutate records.
- [ ] Claim staleness: code changes affecting evidence cause the required claim response.
- [ ] Groom: random pre-commitment is preserved and claims/evidence remain out of scope.
- [ ] Record each scenario’s positive liveness condition and judgment rubric.

**Acceptance gate**

- [ ] The suite covers every originally proposed behavioral risk or explicitly documents why a scenario was replaced.

**Completion record:** commit ___ · validation ___ · notes ___

### [ ] R09 — No Committed Regression Suite Covers Vendor, Installer, or Linter Contracts

**Location:** repository-wide testing infrastructure

**Context and proof basis**

The review reproduced most failures with temporary fixtures. None of those checks currently protects future changes in the repository. `vendor.sh`, `install.sh`, and `lint.sh` are the load-bearing distribution and conformance interfaces.

**Recommended fix**

Create a portable shell regression suite with isolated temporary repositories and target directories. Cover state matrices rather than individual implementation lines. Run it in CI on at least macOS and Linux if both are supported.

- [ ] Vendor matrix: copy/link/check, local edits, force, dirty source, missing/mixed state, argument order, offline remote, atomic failure.
- [ ] Installer matrix: absent/default/extra targets, identical and divergent copies, partial failure, repeat runs.
- [ ] Linter matrix: one good and one bad fixture per owned rule plus parsing edge cases.
- [ ] Add a single documented command for local and CI execution.
- [ ] Avoid new dependencies unless their portability and maintenance justify them.

**Completion record:** commit ___ · validation ___ · notes ___

### [ ] R10 — `cksum` Is an Accidental-Edit Detector, Not a Tamper Seal

**Location:** `.agents/skills/.vendored-manifest` contract and `vendor.sh`

**Context and proof basis**

POSIX `cksum` is portable and appropriate for accidental change detection, but CRC32 is collision-prone. A deliberate adversary can potentially produce different content with the same checksum. The current local-edit feature should not be described as cryptographic integrity.

**Recommended fix**

Choose and document the threat model. If the goal is only preventing accidental overwrite, keep `cksum` and say so. If untrusted-tamper detection is required, use a stronger available digest with a specified portability fallback or a signed release/manifest design.

- [ ] Record the threat-model decision in README and script comments.
- [ ] Remove any language that implies cryptographic authenticity unless implemented.
- [ ] If upgraded, test algorithm/version negotiation across supported platforms.

**Completion record:** decision ___ · validation ___ · notes ___

---

## Human Decision Gate

### [ ] D01 — Licensing and Upstream Permission

**Current state:** intentionally unresolved; no root `LICENSE` file
**Location:** `README.md:109–121`

**Context and background**

The linked-records material is described as a synthesis derived from dpc’s Linked Specs and maan2003’s agentic-claims work. The scripts, linter, and eval suite are original. The public maan2003 repository exposes no license file, and the available dpc source was not verifiable during review. An unlicensed source does not provide a clear basis for applying MIT terms to derivative material. Private permission cannot be inferred from repository content.

The previous root MIT license was removed at the reviewed HEAD. README now says permission is pending and no reuse rights are granted beyond platform terms. That is the safer present state.

**Proof and unknowns**

- No root `LICENSE` exists at baseline `5116497`.
- README records both upstream lineages and the pending-permission state.
- The public `maan2003/public-skills` repository had no license when checked.
- No written permission or sublicensing terms are present in this repository.
- This checklist is an engineering record, not legal advice.

**Recommended resolution**

Keep the current no-license notice until Frank has written permission that clearly covers copying, adaptation, redistribution, and relicensing of the derived material. Preserve the permission evidence outside the public repository if it contains private correspondence; summarize the resulting grant accurately in README. Then add the agreed license, which may or may not be MIT depending on the permission received.

**Decision checklist**

- [ ] Identify every upstream portion incorporated into each skill.
- [ ] Obtain written permission or a compatible upstream license for each derived portion.
- [ ] Confirm the permission covers redistribution and the intended outbound license.
- [ ] Record the decision and scope without publishing private correspondence.
- [ ] Add the root license only after the permission scope is clear.
- [ ] Update README provenance and licensing language to match the final grant.
- [ ] If permission is not obtained, decide whether to rewrite the derived portions independently or retain the no-license state.

**Acceptance gate**

- [ ] Repository license terms are supported by documented rights for every included component.
- [ ] README lineage remains accurate.
- [ ] No badge or metadata claims a license before the root license decision is complete.

**Completion record:** decision ___ · evidence location ___ · commit ___ · notes ___

---

## Final Repository-Wide Completion Gate

Do not close this checklist until all applicable items above are `[x]` or `[N/A]` with rationale.

- [ ] P1 eval false greens are closed before new eval output is cited as evidence.
- [ ] Linter good/bad fixtures prove every mechanical rule it claims to enforce.
- [ ] Vendor and installer state matrices pass on supported macOS and Linux shells.
- [ ] Read-only commands are proven non-mutating across argument permutations and malformed state.
- [ ] Filesystem replacement and cleanup paths are failure-safe.
- [ ] Provenance inputs are sanitized and cannot select an unsafe Git transport.
- [ ] Grooming cannot sample or mutate claims or claim evidence.
- [ ] Behavioral scenarios cover gates, thresholds, claim immutability/staleness, bare activation, and grooming.
- [ ] Authored and generated Markdown complies with repository frontmatter rules.
- [ ] Bash syntax checks pass for every shell script.
- [ ] `git diff --check` passes.
- [ ] ShellCheck runs clean if adopted/available, or its absence remains explicitly documented.
- [ ] README accurately describes actual behavior and limitations.
- [ ] Licensing state matches verified upstream rights.
- [ ] Final review finds no unresolved P1/P2 correctness, safety, or false-green issue.

## Final Completion Record

- Final commit or PR: ___
- Validation environments: ___
- Validation commands/results: ___
- Explicitly deferred items and owners: ___
- Remaining risks accepted by: ___
- Checklist closed on: ___
