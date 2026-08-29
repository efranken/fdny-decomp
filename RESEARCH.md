# RESEARCH.md

High-level, living understanding of the game itself — not the build
infrastructure (`plan.md`) and not per-symbol research records (the
Phase 3 SQLite DB, once it exists). This is the master top-down context:
what this game *is*, how its pieces fit together, and the current
strategy for decomposing it. Update it in place as understanding grows
— this file's job is to let a fresh session (or a fresh VM) get
oriented in one read, without re-deriving everything from scratch.

Empty because nothing's been researched yet — the placeholder
`$GameExePath` in `environment/config.ps1` hasn't been pointed at a
real binary. First real work here happens once that's set.

## Before touching Ghidra: research the game itself

Do this before starting granular decompilation work, not after:

- What is this game — title, platform, engine (if any off-the-shelf
  engine is identifiable), release year, developer
- Does prior art exist — community wikis, existing decompilation or
  reverse-engineering projects, ROM-hacking/modding communities,
  file-format documentation, disassembly notes anyone's already published
- What's the binary's shape at a glance — compiler/toolchain fingerprint,
  obvious subsystems from strings/imports/exports, whether it's a known
  engine's executable versus fully bespoke
- What's actually worth investigating first — pick a top-down strategy
  (e.g. "map main loop and major subsystems first," "start from known
  strings and work backward," "target save/load format first because
  it's small and self-contained") and write it down here, with the
  reasoning, before diving into function-by-function work

## Sections to fill in as research progresses

- **Identity** — title/platform/engine/toolchain, sources for each claim
- **Subsystem map** — major pieces (rendering, input, game logic, save
  format, etc.) and what's known/unknown about each
- **Strategy** — current top-down plan for attacking decompilation, and
  why; revise this as findings change the picture, note what changed
  and when
- **Open questions** — the things blocking progress or worth
  investigating next
- **Key findings** — load-bearing facts worth surfacing at the top
  level rather than buried in the Phase 3 DB (that DB is for granular
  per-symbol/function evidence; this is for the handful of things any
  session needs to know immediately)
- **Blocked tasks** — anything timeboxed and set aside rather than
  solved: what it was, what was tried, why it stalled
- **Needs human attention** — findings or decisions that need a
  person's judgment call, not another research pass. Whoever reads
  this next (human or agent) should be able to tell what happened and
  what's waiting on them from this section alone.
