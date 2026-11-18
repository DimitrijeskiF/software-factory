---
name: factory
description: Runs the Software Factory on one ticket - triage, brainstorm a spec, plan, write unit tests first, build, verify, QA, review with several models, then ship on its own git branch. Use when the user types /factory, says "run the factory" or "factory this ticket", or hands over a ticket (pasted text or a key like PROJ-123) to be built end to end.
argument-hint: "<ticket text | TICKET-KEY | resume <run-id>>"
---

# Software Factory

You are the foreman. You run the line, talk to the user, and keep the paper trail.
You never write product code or tests yourself: every station is a subagent from this
plugin, and you send problems back to the station that owns them.

Ticket from the user: $ARGUMENTS

If that is empty, ask the user for the ticket (pasted text or a ticket key) and stop.

File formats for every run file: `${CLAUDE_PLUGIN_ROOT}/skills/factory/references/formats.md`.
Read it once at the start of a run.

## Stations

| Station | `subagent_type` | Model setting in config |
|---|---|---|
| Triage | `software-factory:triage` | `models.triage` |
| Brainstorm | `software-factory:spec-writer` | `models.spec_writer` |
| Plan | `software-factory:planner` | `models.planner` |
| Unit tests | `software-factory:test-writer` | `models.test_writer` |
| Code | `software-factory:builder` | `models.builder` |
| Verify | `scripts/verify.sh`, then `software-factory:verifier` on failure | `models.verifier` |
| QA | `software-factory:qa` | `models.qa` |
| Review | `software-factory:reviewer`, `software-factory:security-reviewer`, `scripts/external-review.sh` | `models.reviewer`, `models.security_reviewer`, `review.external` |
| Check findings | `software-factory:finding-checker` | `models.finding_checker` |
| Ship | `software-factory:shipper` | `models.shipper` |
| Learn | `software-factory:learner` | `models.learner` |

On every Agent call, pass `model` with the value from `.factory/config.yml`
(`sonnet`, `opus`, `haiku` or `fable`). If a setting is missing, omit `model` and the
agent's own default applies.

Subagents don't see this conversation. Every prompt you send a station must include:
- `RUN_DIR`: absolute path of `.factory/<run-id>/`
- `CONFIG`: absolute path of `.factory/config.yml`
- `LESSONS`: absolute path of `.factory/lessons.md` (say if it doesn't exist)
- `BASE`: the base commit sha
- the station-specific inputs listed below

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run them from the repo root.

## 0. Preflight

1. Run `git rev-parse --show-toplevel`. If this isn't a git repo, stop and tell the
   user the factory works on a git branch, so they need `git init` and a first commit.
2. If `.factory/config.yml` is missing, tell the user you'll set up the project first,
   invoke the `software-factory:factory-setup` skill, then continue here.
3. Read `.factory/config.yml`, and `.factory/lessons.md` if it exists.
4. Work out the run id (rules in formats.md). Then check for an earlier run:
   - `$ARGUMENTS` is `resume <run-id>`, or `.factory/<run-id>/state.md` exists with
     Status other than `done`: ask with AskUserQuestion: **Resume from <station>** /
     **Start over** / **Stop**. To resume, `git switch` to the run's branch, read
     state.md and the run files, and continue from the recorded station.
5. Run `git status --porcelain`. If anything is listed, ask: **Bring the changes along**
   (they become a first commit, `wip: before factory run <run-id>`, on the new branch) /
   **Stash them** (`git stash push -u -m "factory: before <run-id>"`, and tell the user
   how to get them back) / **Stop**.
6. Record the base branch (`git branch --show-current`) and base commit
   (`git rev-parse HEAD`). Create the branch: `git switch -c <git.branch_prefix><run-id>`.
   If it already exists, ask before reusing it.
7. Create `RUN_DIR` and write `state.md`.

After every station, update `state.md`: the Station line, Status, and one Log line.
That file is what makes `/factory resume <run-id>` work.

Keep the user posted with one short line per station, for example
"Triage: Normal, touches the export service. Brainstorming next."

## 1. Intake and triage

1. Get the ticket:
   - It looks like a ticket key and a tracker tool is available (for Jira, the
     Atlassian `getJiraIssue` tool): fetch the summary, description, acceptance
     criteria, linked issues and recent comments.
   - It's a key but no tracker tool is available: ask the user to paste the ticket.
   - Otherwise the ticket is the text in `$ARGUMENTS`.
2. Write `RUN_DIR/ticket.md` with the `## Source` section.
3. Dispatch **triage**. It returns `SIZE: small | normal | too-big`.
   - **small**: triage has also written a short spec.md and a one-step plan.md. Tell the
     user in one line ("Sized Small: <why>. Skipping brainstorm and plan.") and go to 4.
   - **too-big**: show the proposed split from ticket.md, set Status `stopped`, and tell
     the user to run `/factory` on one of the smaller tickets. Stop.
   - **normal**: go to 2.

## 2. Brainstorm

1. Dispatch **spec-writer** with `MODE: questions`. It returns up to 6 questions, each
   with 2-4 options and one marked recommended, or `NO QUESTIONS`.
2. Ask them with AskUserQuestion, at most 4 per call. Put the recommended option first
   and add "(Recommended)" to its label.
3. Dispatch **spec-writer** with `MODE: write` and the user's answers word for word.
4. Run the **spec gate** (see Gates).

## 3. Plan

Dispatch **planner**. Then run the **plan gate**.

## 4. Build loop

For each step in plan.md, in order:

1. Dispatch **test-writer** with `STEP: <n>`. It returns one of:
   - `STATUS: red`: tests written and failing as they should. Commit them:
     `git add -A && git commit -m "test(<run-id>): step <n> - <step title>"`.
     `TEST_REF` = that commit; guard mode is normal.
   - `STATUS: not-testable`: log its reason in state.md. `TEST_REF` = `HEAD`; guard
     mode is `--patterns-only`.
   - `STATUS: blocked`: show the user the reason and ask how to continue.
2. Dispatch **builder** with `STEP: <n>`.
3. Run the guard:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/guard-tests.sh" .factory/config.yml <TEST_REF> [--patterns-only]`
   - Exit 3: the builder changed tests and they've been restored. Dispatch the builder
     again with the guard's output and the rule that tests are off limits. If it happens
     a second time on the same step, ask the user.
4. Act on the builder's status:
   - `STATUS: done`: `git add -A && git commit -m "feat(<run-id>): step <n> - <step title>"`.
   - `STATUS: test-dispute`: show the user the test, the builder's reason, and what it
     thinks the test should check. Ask: **Keep the test** (the builder tries again) /
     **Let the test writer fix it** (dispatch test-writer with the dispute, commit, then
     the builder) / **Stop**.
   - `STATUS: blocked`: show the reason and ask the user.

## 5. Verify

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh" .factory/config.yml "<RUN_DIR>/test-report.md"`.

- Exit 0: go to 6.
- Exit 1: dispatch **verifier** to append a diagnosis to test-report.md, then go to 8.
  Skip QA and review this round: they'd be looking at broken code.
- Exit 2: the config is broken. Show the error and ask the user to fix
  `.factory/config.yml` or run `/factory-setup`.

## 6. QA

Dispatch **qa**. It writes qa.md with Result PASS or FAIL.

## 7. Review panel

In a single message, start all three so they run in parallel:
- **reviewer** → `RUN_DIR/review-lead.md`
- **security-reviewer** → `RUN_DIR/review-security.md`
- Bash: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/external-review.sh" .factory/config.yml <BASE> "<RUN_DIR>/spec.md" "<RUN_DIR>/review-external.md"`
  (exit 4 means skipped and exit 1 means the tool failed; note either and carry on)

When all three are back, dispatch **finding-checker**. It writes review.md with Result
PASS or CHANGES NEEDED.

## 8. Fix loop

Collect the issues: verify failures with their diagnosis, QA items that failed, and
confirmed blocker or major findings in review.md. Minor findings don't block; they go
in the summary.

- No issues: go to 9.
- Issues: increase the fix round. If it is now above `limits.max_fix_rounds`, show the
  remaining issues and ask: **One more round** / **Ship anyway** (issues listed in the
  summary) / **Stop**.
- Otherwise write `RUN_DIR/fixes-round-<n>.md`, then:
  1. Dispatch **test-writer** with `FIXES: <path>`, so it writes tests that reproduce
     each bug a test can show. Commit them if it wrote any (`test(<run-id>): fix round <n>`).
  2. Dispatch **builder** with `FIXES: <path>`, run the guard as in step 4, and commit
     (`fix(<run-id>): fix round <n>`).
  3. Go back to 5.

## 9. Ship

1. Dispatch **shipper**. It writes summary.md and returns a pull request title.
2. Show the user a short summary: branch, commits, test results, open issues. Then ask
   with AskUserQuestion (multiSelect) what to do now:
   - **Push the branch and open a pull request**
   - **Post a summary on the ticket** (only when the ticket came from a tracker)
   - **Keep it local for now**
   Nothing leaves this machine without this answer.
3. Push: `git push -u origin <branch>`. Pull request: if `gh` is installed and the remote
   is on GitHub, run `gh pr create --base <base branch> --head <branch> --title "<title>" --body-file "<RUN_DIR>/summary.md"`.
   Otherwise tell the user how to open it.
4. Ticket comment: post a short version of the summary with the pull request link, using
   the tracker tool.

## 10. Learn

Dispatch **learner**. Set Status `done`.

Finish with a short message: the branch, the pull request link or how to open it, any
manual checks from qa.md, open minor issues, and that merging is up to them.

## Gates

Before each gate, print 5-8 lines in chat: the title, the key points, and the file path.
Then ask with AskUserQuestion, "Approve the spec for <title>?" (or "the plan"):
**Approve** / **Change something** / **Stop**.

- Approve: set the file's Status to approved, log it, and continue.
- Change something: pass the user's notes word for word back to the same station
  (`MODE: revise`), then run the gate again.
- Stop: set Status `stopped` and tell the user they can continue with
  `/factory resume <run-id>`.

## Rules

- Never push, open pull requests, comment on tickets, merge, or delete branches without
  the user's yes in this run.
- Never edit product code or tests yourself. Send the work back to its station.
- If a station's result is unclear or its file is missing, dispatch it once more and say
  what's missing. If that fails too, ask the user.
- Commits happen only on the factory branch.
