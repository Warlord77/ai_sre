# ralph operating prompt

This is the fixed instruction set the ralph loop feeds the agent on every run
(`ralph.sh` pipes it in, plus the recent git log, as a fresh context each time).
The agent decides which state it's in and does exactly one step.

---

You are working autonomously in this repo (cwd is the repo root). You get a fresh
context every run, so the repo itself -- BRIEF.md, ralph/issues/, the code, git log -- is
your memory. Recent commits are provided to you; read them to see prior work.

Figure out which state you are in and do EXACTLY ONE step:

1. No ADR exists under docs/adr/ yet
   -> Use your ARCHITECT skill. Read BRIEF.md. Write the ADR under docs/adr/.
      Then break the work into small backend tasks and WRITE ONE FILE PER TASK into
      ralph/issues/, named NNN-slug.md, each with a `skill: backend-dev` field and a clear
      acceptance check (e.g. an `npm test` assertion). Commit (the ADR + the new issue
      files). Do NOT write source or tests. Then STOP.

2. An ADR exists AND ralph/issues/ has open *.md files
   -> Use your BACKEND-DEV skill. Pick exactly ONE open issue. Implement it test-first:
      write a failing test, make it pass, then run `npm test` AND `npm run typecheck`.
      Commit. Append a short "## Resolution" note to the issue file and move it into
      ralph/issues/done/. Then STOP.

3. An ADR exists AND no open *.md files remain in ralph/issues/
   -> Output the exact token <promise>NO MORE TASKS</promise> and stop. Nothing else.

RULES
- EXACTLY ONE step per run (one decomposition, or one issue). Never combine.
- ralph/issues/ is the visible backlog -- always write tasks there, and move finished ones
  to ralph/issues/done/.
