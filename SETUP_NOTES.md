# SETUP_NOTES.md

A running log of build/infrastructure friction — things a human should
review before the next `deploy_vm.ps1` run. Distinct from `RESEARCH.md`
(game domain) and `plan.md` (overall plan/phases): this file is
specifically for "here's what was missing or broke during this run,"
kept short enough to scan in ten seconds.

If you (agent) can safely fix something yourself — install a missing
tool via the existing `get_*`/`install_*` convention, update
`provision.ps1`/`config.ps1` to include it for next time — just do
that directly, per `CLAUDE.md`'s operating guidance, and note what you
did here for visibility. Use this file for things that need a human's
judgment call instead: a suggested approach you're not sure about, a
tradeoff, something that felt too risky to change unilaterally.

Empty so far — nothing's been run against a real game binary yet.

## Format

One entry per finding:

```
## YYYY-MM-DD — short title
What happened / what was missing.
What you did about it (if anything), or what you're suggesting.
```
