---
name: assurance-records-bug-hunt
description: Use when explicitly asked to hunt implementation bugs or audit crash, retry, concurrency, or recovery behavior under the assurance-records convention. Not for ordinary implementation, routine review, or record upkeep.
---

# Bug Hunt

Find concrete ways a named operation can harm its users. The default output
is a concise findings report and useful executable witnesses. A hunt needs
neither an existing claim nor a new one.

Read `assurance-records` (`../assurance-records/SKILL.md`) first. Its discovery
and authority rules apply. A hunt request alone authorizes investigation, not
product repairs or claim creation. If fixes were also requested, carry them
through with before/after evidence. Bare skill loading starts no hunt.

When existing claims or their evidence are involved, load
`assurance-records-claims` (`../assurance-records-claims/SKILL.md`) separately
before evidence reads. That skill owns evidence, verdicts, staleness, and
repair. A hunt may consult prior bugs; requested independent verification
must follow its fresh-assessment procedure instead.

## 1. Bound the investigation

Start from the surface the user named: an operation, subsystem, or change and
its affected consumers. Identify the harms worth investigating: lost or
corrupted durable state, duplicate effects, false success reports, abandoned
accepted work, permanently stuck operations, or effects charged to the wrong
owner. Add harms required by the project's contracts.

State the scope, prioritized harms, and stopping condition before hunting.
Use the supplied budget; otherwise investigate the named surface and its
direct recovery paths, stopping after its selected failure cases are checked
or a concrete dependency prevents further checking. A broad request needs a
bounded first slice, chosen from impact and code evidence. Expand only enough
to establish the same failure mechanism; report other leads for later work.

Locate entry points, background work, startup, replay, and cancellation.
Keep a small operation-by-harm table in working notes when it helps reveal
coverage gaps. Unexamined cells are gaps, not a mandate for more records or
automatic follow-up investigations.

## 2. Establish the fault model

Read governing records, implementation, deployment configuration, and relevant
dependency contracts. Distinguish established facts from unconfirmed premises.
Consider crashes, restarts, overlapping requests, cancellation, and transient
I/O errors where the actual system permits them. Use honest counterparties as
a scoped reliability investigation; it does not establish security coverage.

Identify what survives interruption, which steps are atomic, who retries each
obligation, and what ordering clocks or identifiers actually provide. A claim
of permanent wedging needs a reachable state that remains stuck after the
allowed recovery, not merely a schedule that fails forever. State necessary
eventual-recovery or scheduling assumptions.

Unconfirmed deployment assumptions yield conditional concerns until supported.
Mark unavailable checks and continue independent investigation. Coverage gaps
do not accept risk or narrow a governing guarantee; follow the claims skill
for residual acceptance and any authorized evidence update.

## 3. Challenge the execution paths

Trace each selected harm through reachable code, including downstream
consumers and the pinned implementation of dependencies the argument relies on.
Useful questions:

- After work is accepted, what retries it when a detached task fails?
- Does startup reconstruct every necessary obligation from durable facts?
- Can an operation run before its protecting guard becomes effective?
- What does a success response promise, and is that effect already established?
- Does a status field report durable fact, live observation, or echoed input?
- Can a delayed retry overwrite a newer result or repeat an effect?
- Can shared work cross an ownership boundary or charge the wrong resource?

Use existing findings as leads and cite their witnesses. Finding no new defect
is valid; there is no bug quota. A conflict in intended behavior is a question
about requirements, not proof that the implementation is wrong.

## 4. Establish evidence

Prefer a small witness that calls real entry points and checks observable
effects. Capture the revision, initial conditions, inputs or schedule, expected
behavior, and observed violation. Preserve a runnable command and the witness
in the requested artifact location or the project's normal test locations.
Keep scratch state isolated; cleanup must preserve the evidence being reported.

Choose tests, generated search, or formal tools according to the property and
available infrastructure. A model must justify its connection to implementation,
including atomic steps. Replay its counterexample against reachable code where
possible; label the parts supported only by the model or code reading.

For a new search harness, exercise a meaningful broken variant in an isolated
copy and show that its oracle detects the violation. Follow the claims skill's
`search` evidence rules. A model mutation checks the model harness; detecting a
product mutation also needs current model-to-code correspondence. Run the saved
procedure as a future agent would, then restore scratch changes. If the check
cannot run, report that gap; a plausible witness is not an executed one.

## 5. Report and stop

Report the scope, fault assumptions, checks actually run, and remaining gaps.
Separate demonstrated implementation defects, conditional concerns, model-only
counterexamples, and cases checked without a counterexample. Each defect needs
its harm, reachable trace, evidence, and affected paths; include fix direction
when supported. Name unavailable tools and untested conditions explicitly.

A clean bounded hunt reports no counterexample in that coverage. It supplies
neither an independent claim pass nor a guarantee of bug absence. Preserve
existing counterexamples and fixed claim statements under the claims rules.
Propose a durable claim only when it qualifies and lacks a stronger owner.

Use the existing report or issue conventions; one report can cover the hunt.
No automatic claim tree, feature-map corpus, companion bug index, or generated
verification skill is required. Finish at the stated boundary with usable
evidence and visible gaps.
