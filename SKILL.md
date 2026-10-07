---
name: reviewable-diffs
description: Plan and execute code changes so the resulting pull request contains only functional changes — a minimal diff, no formatting churn, no invented features, backed by a truth table, unit tests covering every interaction, and a tracked implementation status. Use this whenever code is being written, modified, refactored, or fixed inside an existing repository; whenever the change will end up in a PR or code review; whenever work is being resumed from a previous session; and whenever the user mentions diff noise, review burden, scope creep, or hallucinated features. Default to using it for any multi-step or multi-file repo change, even when the user doesn't ask for tests, a truth table, or status tracking by name.
---

# Reviewable Diffs

The goal of this skill is that a human reviewer reading the PR sees only what functionally changed — nothing they have to skim past, and nothing they didn't ask for. Every line in the diff should be traceable to a stated requirement.

## Step 1 — Restate before building

Before writing any code, restate in your own words:

- What the user is asking for, as a list of discrete requirements.
- What you understand the current behavior to be.
- What the change will and will not touch.
- Any assumption you're making that the user hasn't confirmed.

Then stop and wait for confirmation. This exists because most scope creep is a misunderstanding that was never surfaced — catching it here costs one message instead of a full review cycle.

## Step 2 — Scope discipline

Requirements come only from the user's stated requests and from what already exists in the repository. Do not add error handling, config options, logging, abstractions, accessibility attributes, or "while I was in there" fixes that weren't asked for, however reasonable they seem.

General knowledge of the language, framework, and standard library is expected and fine — that's implementation, not requirements. But anything that must actually exist to work (an internal function, a config key, a package export, a database column, an API endpoint) gets verified against the repository or the library's real documentation before you depend on it. Do not invent module paths, function signatures, or CLI flags to make an approach work.

If you find a real problem outside the requested scope, list it at the end as a separate finding. Don't fix it in this branch.

## Step 3 — Uncertainty protocol

When you don't know something — an ambiguous requirement, an unclear existing behavior, an API you can't verify — write **Uncertain**, say specifically what you're uncertain about, and ask. Do not pick the most likely answer and proceed silently.

Uncertainty is cheap at this stage and expensive after the code is written. An unanswered question that becomes a guess becomes a defect the reviewer has to catch.

## Step 4 — Branch

Create a branch on the target repository before making any change, named after the change (`fix/`, `feat/`, `chore/` plus a short slug). Confirm which base branch to cut from if it isn't obvious.

## Step 5 — Truth table

Build a truth table before writing implementation code. It's the contract the tests and the implementation are both written against, and building it first is what exposes the cases nobody thought about.

Enumerate every input or interaction against every relevant precondition, and give the expected outcome for each row:

| # | Input / interaction | Preconditions / state | Expected outcome | Test name |
|---|---------------------|-----------------------|------------------|-----------|

Include invalid input, empty and boundary values, and error states — not just the happy path. For UI components, enumerate prop and state combinations (loading, empty, error, populated, disabled) rather than boolean logic.

Where an expected outcome isn't specified by the user and isn't already determined by the existing code, mark the row **Uncertain** and ask rather than filling it in.

Share the table and get agreement on it before moving on.

## Step 6 — Tests

Write unit tests covering every row of the truth table, one test per row, named so the row is identifiable from the test name. For components, cover the layout and state expectations the same way.

Write the tests before the implementation and confirm they fail for the right reason. A test written after the code tends to encode what the code does rather than what was asked for.

## Step 7 — Implement

Write the minimum code that makes the tests pass. Then run the full existing test suite, not just the new tests, and report anything that broke.

## Step 8 — Keep the diff functional only

Do not reformat, restyle, or reorganize anything. Specifically: no running formatters or linters across files, no reordering or regrouping imports, no renaming unrelated variables, no whitespace or line-ending normalization, no reflowing untouched lines, no comment cleanup, no dependency bumps.

Match the surrounding code's existing style even where it disagrees with your defaults or with the project's configured formatter — a formatter run buried in a functional PR is exactly the noise this skill exists to prevent.

If a formatting change is genuinely unavoidable (an auto-formatting pre-commit hook, a file that won't parse otherwise), isolate it in its own commit with a message saying why, and call it out in the summary.

Before finishing, read your own diff line by line and remove anything that isn't required by a truth table row.

## Step 9 — Repo edit log

The edit log is **history**: append-only, never edited or rewritten. Current state lives in the implementation status file (Step 10) and never appears here. Keeping that boundary sharp is what stops the two files from drifting apart and contradicting each other.

Check the repository for an existing change log or edit log. If one exists, follow its established format and heading conventions exactly; only the content should be new.

If none exists, create `REPO_EDIT_LOG.md` at the repository root, with a short header explaining that each future change appends an entry here.

Append one entry per change set:

```
## [ISO 8601 timestamp] — <branch name>
**What changed:** <summary of the functional change>
**Why:** <the requirement or problem it addresses>
**Files touched:** <list>
**Tests added:** <list or count>
**Deliberately not changed:** <in-scope-adjacent things you left alone, and out-of-scope findings>
**Uncertainties:** <anything still unresolved, or "none">
```

The "deliberately not changed" line matters as much as the rest: it tells the next reader that an omission was a decision, not an oversight.

## Step 10 — Implementation status

Maintain `IMPLEMENTATION_STATUS.md` as a snapshot of **current state only** — never history, which belongs in the edit log. Overwrite it; do not append. Update it in the same commit as the code change, never as a follow-up step, because a tracker matters most on the runs that get interrupted and those are exactly the runs where a deferred step gets dropped.

Scope the file to the feature or work stream, not the whole repository (`docs/status/<feature>.md` or alongside the feature's code). A single root-level status file is edited by every branch, so it conflicts on merge in almost every PR, and prose conflicts are tedious to resolve.

Write for the next agent session as much as for a human — a human reviewer already has the PR and the diff. That means pointers and state, not narrative.

One row per truth table row:

| Requirement / truth table row | Status | Test | Notes |
|---|---|---|---|

- Status is one of: **Not started / In progress / Blocked / Done.**
- **Blocked** requires a reason and what would unblock it.
- **Done** requires a passing test. If there's no test, it isn't Done — "done" must not be allowed to mean "the agent believes it finished."
- Anything you could not verify is marked **Uncertain**, not assumed Done.

End the file with a single **Next step:** line naming the one thing the next session should pick up.

If the work is contained in a single PR and won't span sessions, this file is overhead — skip it and add a `**Next step:**` field to the edit log entry instead.

## Final summary

Report back with: the branch name, the truth table, the tests and their results, the files touched, the log entry you appended, the current status table, anything marked Uncertain, and any out-of-scope findings you left alone.
