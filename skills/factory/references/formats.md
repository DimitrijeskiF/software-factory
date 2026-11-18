# Software Factory file formats

Every factory run keeps its files in `.factory/<run-id>/` at the project root. Each
station writes only its own file, in the format below. Keep files short and factual:
the next station and the user both read them.

Run ids: a ticket key as-is (`PROJ-123`), otherwise `YYYY-MM-DD-<slug>` from the
first few words of the ticket (`2026-11-12-add-csv-export`).

---

## state.md (written by the foreman)

```markdown
# Factory run: PROJ-123
- Ticket: Jira PROJ-123 | pasted text
- Size: small | normal | too-big
- Base: main @ 1a2b3c4
- Branch: factory/PROJ-123
- Status: in progress | waiting for you | stopped | done
- Station: triage | brainstorm | plan | build step 2 of 4 | verify | qa | review | fix round 1 | ship | learn
- Fix round: 0 of 3

## Log
- 2026-11-12 09:14 triage: normal (touches export service and reports page)
- 2026-11-12 09:20 spec approved
```

---

## ticket.md (foreman writes Source; triage appends the rest)

```markdown
# Ticket: <title>

## Source
<the ticket exactly as given or fetched: title, description, acceptance criteria, comments>

## Triage
Size: normal
Why: <one or two sentences>
Code it touches:
- src/reports/export.ts - builds the report rows
- src/reports/ReportPage.tsx - the button goes here

## Split (only when too big)
1. <title> - <one-line scope>
2. ...
```

---

## spec.md (spec writer; triage writes a short one for small tickets)

```markdown
# Spec: <title>
Ticket: PROJ-123 · Size: normal · Status: draft | approved

## Goal
One or two sentences: what changes for the user, and why.

## Scope
- In: ...
- Out: ... (things that look related but this ticket won't do)

## Behaviour
How it should work, in plain words, including errors and edge cases.

## Done when
Numbered. Each item can be proven by a test, a command, or a screenshot.
1. ...
2. ...

## Decisions
- <question> → <answer> (decided by: user | spec writer)

## Code touched
- path/to/file - why
```

---

## plan.md (planner; triage writes a one-step plan for small tickets)

```markdown
# Plan: <title>
Spec: spec.md · Steps: 3

## Step 1: <short title>
- Covers done-when: 1, 3
- Files: src/reports/export.ts (change), src/reports/export.test.ts (new)
- Unit tests to write:
  - exports one CSV row per report line: <what it proves>
  - escapes commas and quotes in cell values: <what it proves>
- Build: what to change, in 2-5 lines.
- Not testable: <only for docs, config or wiring with no logic; say why and how QA will check it>
```

Steps are ordered so each one leaves the project working. Aim for 1-8 steps.

---

## fixes-round-N.md (foreman, before each fix round)

```markdown
# Fixes: round 1
1. [verify] test failed: export.test.ts "escapes quotes" - see test-report.md diagnosis D1
2. [qa] done-when 3 not met: empty report shows a broken file instead of a message
3. [review R2, major] src/reports/export.ts:42 - dates exported in local time, spec says UTC
```

---

## test-report.md (written by scripts/verify.sh; the verifier may append a diagnosis)

```markdown
## Diagnosis
### D1 test - export.test.ts "escapes quotes"
Cause: quote characters are not doubled in escapeCell (src/reports/export.ts:31).
Fix: double every `"` inside a quoted cell.
Related to this change: yes | probably not (code not touched by the diff)
```

---

## qa.md (QA)

```markdown
# QA: <title>
Result: PASS | FAIL

| # | Done-when item | Result | Proof |
|---|---|---|---|
| 1 | One CSV row per report line | pass | `npx vitest run src/reports/export.test.ts` → 6 passed |
| 3 | Empty report shows a message | FAIL | Ran export on empty fixture: 0-byte file, no message |
| 4 | Button matches design | needs manual check | No UI runner in this project. Steps: open /reports, click Export |
```

FAIL when any item fails. "needs manual check" does not fail the run; it goes into the summary.

---

## review-lead.md, review-security.md (reviewers) and review-external.md (script)

```markdown
# Review: lead
Findings: 2

### F1 [major] src/reports/export.ts:42 - dates exported in local time
What is wrong, the input that breaks it, why it matters, and the fix.

### F2 [minor] ...
```

Severity: **blocker** (wrong result, data loss, security hole, crash on a normal path),
**major** (wrong in a realistic case, missing a done-when item, test that proves nothing),
**minor** (worth fixing, safe to merge without).

---

## review.md (finding checker)

```markdown
# Review result
Result: PASS | CHANGES NEEDED
Confirmed: blocker 0 · major 1 · minor 2 · Dropped: 3

## Confirmed
### R1 [major] src/reports/export.ts:42 - dates exported in local time (from: lead F1, external 2)
What is wrong, what you checked to confirm it, and the fix to make.

## Dropped
- security F2 - input is already validated in parseRequest (src/api/reports.ts:18)
```

PASS when there is no confirmed blocker or major finding.

---

## summary.md (shipper; also the pull request body)

```markdown
# <title>
Ticket: PROJ-123

## What changed
- ...

## Why
...

## How it was tested
- Unit tests added: 9 in 2 files
- Verify: test pass · lint pass · typecheck pass · build pass
- QA: 4 of 5 done-when items proven; 1 needs a manual check (below)

## Review
- Lead review (opus), security review (sonnet), second opinion (gemini | skipped)
- Fixed during review: dates now exported in UTC
- Open minor issues: ...

## Check it yourself
1. ...
```

---

## .factory/lessons.md (learner; read by every station)

```markdown
# Factory lessons
Read by every factory run in this project. Newest first. Keep it under 40 lines.

- 2026-11-12 · `npm test` runs e2e too and takes 6 minutes; use `npm run test:unit` for single files (PROJ-123)
- 2026-11-10 · Dates in this codebase are always UTC; use `toUtcIso()` from src/lib/dates.ts (PROJ-118)
```
