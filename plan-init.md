# Plan

AI-assisted decompilation of a video game using Ghidra, GhidrAssist,
and Claude Code connected to GhidrAssist.

Phase 1 and 1.5 are well-defined. Later phases are directional and
will be revised as work progresses — agents should update this file
in place rather than treat it as fixed. If you discover something that
changes the plan, change the plan — don't just note the discovery and
keep following stale guidance.

`RESEARCH.md` is the companion file for the game itself: what it is,
its subsystem map, current top-down decompilation strategy, open
questions. This file (`plan.md`) is the infrastructure/build plan;
`RESEARCH.md` is the domain understanding. Keep them separate.

This repo reaches the VM as a plain file copy via the Packer file
provisioner (see `environment/packer/windows-server.pkr.hcl`), not a
clone of this repo — there's no remote and no push/pull with the dev
machine. `provision.ps1` does `git init` a *local-only* repo on the VM
(git itself is installed there too, Phase 3) so the agent can track its
own changes as it runs, but that history never syncs back here. If you
edit `plan.md`, `RESEARCH.md`, or `CLAUDE.md` while working on the VM,
those edits only exist on the VM until someone copies them back by hand.

## Phase 1 — Repo scaffolding

- [x] `environment/scripts/get_ghidra.ps1` — download Ghidra
- [x] `environment/scripts/get_ghidrassist.ps1` — download GhidrAssist
- [x] `environment/scripts/get_claude.ps1` — download Claude Code (not run yet, used in later phase)
- [x] `environment/scripts/install_ghidra.ps1`
- [x] `environment/scripts/install_claude.ps1`
- [x] `environment/scripts/get_fdny.ps1` — stage FDNY game resources (zip + `.rb` save) into `environment/fdny/`
- [x] `environment/scripts/common.ps1` — shared download/extract helpers
- [x] `environment/config.ps1` — central user-tweakable params, incl. placeholder game `.exe` path
- [x] Test: get + install Ghidra
- [x] Test: get + install GhidrAssist
- [x] Claude get/install scripts: no test required this phase
- [x] `get_fdny.ps1`: speedrun.com blocks scripted downloads (Cloudflare JS
      challenge) — script stages `environment/fdny/` and prints manual
      download instructions instead of fetching directly; auto-extracts once
      the files are placed by hand

## Phase 1.5 — Wire up GhidrAssist + Claude Code — done

GhidrAssist (chat panel inside Ghidra) and GhidrAssistMCP (MCP server inside
Ghidra, exposes Ghidra's RE functions as tools) are separate extensions.
The connection to Claude Code runs through GhidrAssistMCP, not GhidrAssist.

Initially assumed enabling a Ghidra extension (File > Install Extensions +
Configure Plugins) required manual GUI clicks. Verified that's false: diffed
Ghidra's per-user tool config (`_code_browser.tcd`) before/after enabling
both extensions by hand, found it's just two `<INCLUDE CLASS="..."/>` lines
plus unpacking the extension zip into Ghidra's user `Extensions/` folder —
both fully scriptable. Proved it with a complete from-scratch rebuild (wiped
`environment/local/tools/`, all downloads, and Ghidra's AppData state; reran
every script) — Ghidra came up with both plugins active and the MCP server
self-started on port 8080, zero manual steps.

- [x] `environment/scripts/get_jdk.ps1` / `install_jdk.ps1` — Ghidra needs a
      JDK to launch and doesn't bundle one; this was a Phase 1 gap, fixed
      here. Pinned to Adoptium Temurin 21 "latest" (not version-coupled to
      Ghidra the way GhidrAssist is).
- [x] `environment/scripts/get_ghidrassistmcp.ps1` — download GhidrAssistMCP
- [x] `environment/local/scripts/config_ghidra.ps1` — headlessly creates a
      Ghidra project imported from `$GameExePath` via `analyzeHeadless`,
      writes `$GhidraProjectName` back into `config.ps1`. Also what creates
      Ghidra's default per-user tool config as a side effect, which
      `enable_ghidrassist.ps1` depends on existing. Smoke-tested against
      `notepad.exe` (full import + analysis succeeded) both standalone and
      as part of the full rebuild; reverts cleanly once a real
      `$GameExePath` is set.
- [x] `environment/local/scripts/enable_ghidrassist.ps1` — unpacks
      GhidrAssist/GhidrAssistMCP straight from `environment/downloads/` into
      Ghidra's user `Extensions/` folder and patches `_code_browser.tcd` to
      enable both plugin classes. Idempotent (checked against the live file:
      re-running after a GUI-driven enable was a byte-for-byte no-op).
      Supersedes `install_ghidrassist.ps1` / `install_ghidrassistmcp.ps1`
      (deleted — they staged zips into the *install's* `Extensions\Ghidra`
      folder, which turned out to only cause a spurious "extensions found"
      dialog on launch since Ghidra never actually consumes them from there
      without the GUI install step).
- [x] `environment/local/scripts/run_ghidra.ps1` — launches Ghidra with
      `JAVA_HOME` set (no system-wide JDK on this machine); `-OpenProject`
      opens `$GhidraProjectName` directly, skipping the project picker.
- [x] `environment/local/scripts/connect_claude_mcp.ps1` — registers
      GhidrAssistMCP's SSE endpoint (`http://localhost:8080/sse`) as a
      project-scoped MCP server via `claude mcp add`, written to `.mcp.json`
      (tracked in git, so it's shared with anyone who clones the repo).
- [x] Full connection test: with Ghidra open on the notepad project,
      `GhidrAssistMCPServer` logged `Server state: STARTED` on port 8080
      unprompted; `curl http://localhost:8080/sse` returned a valid MCP SSE
      handshake (`event: endpoint`). `.mcp.json` registration confirmed via
      `claude mcp get`.
- [ ] One remaining non-scriptable step, by design: Claude Code shows new
      project-scoped `.mcp.json` servers as "Pending approval" until a user
      interactively approves them (`/mcp` in a Claude Code session in this
      repo) — a deliberate trust gate, not something to script around.

## Phase 2 — Packer build — done

Branch: `phase2-packer-hyperv`.

`packer build` succeeds end-to-end from a clean slate: JDK, Ghidra,
GhidrAssist, GhidrAssistMCP (both plugins enabled, verified in the exported
VM's tool config), and Claude Code all baked in, zero manual GUI steps.
Build artifact: `C:\packer-output\fdny-decomp` (outside the repo — see
`environment/packer/README.md`).

Blocker hit early: this shell had no Hyper-V rights at all (not admin, not
`Hyper-V Administrators`), and VM creation needs interactive elevation —
can't script around that. User relaunched the whole session elevated
(`Enable-WindowsOptionalFeature ... Microsoft-Hyper-V-Management-PowerShell`
was also needed — platform was on, the PowerShell module wasn't).

ISO sourcing changed from the original assumption: Microsoft's Server 2025
eval page now gates the ISO behind a registration/lead-capture form (no
stable direct link — confirmed by resolving the fwlink and landing on
`info.microsoft.com/ww-landing-...`). Server 2022's eval still has a working
static link (verified live, HTTP 200, ~5GB) — used that instead. SHA256
pinned once downloaded.

Failures hit and fixed, in order (each one real, verified against actual
tool output — see [[feedback-verify-dont-assert]]):

1. **Hyper-V can't attach ISOs/VHDs from Google Drive.** This repo lives on
   a cloud-sync drive (G:\); `Add-VMDvdDrive` failed with "Access is
   denied" — VMMS can't set the NTFS ACLs it needs on a cloud-sync
   filesystem. Fix: Packer's ISO cache and `output_directory` moved to
   `C:\packer-cache` / `C:\packer-output` (real local NTFS). This is a
   general constraint for this repo, not just Packer — anything needing
   Hyper-V-managed storage has to live off the Drive-synced path.
2. **No CD-image tool for `cd_files`.** Packer needs `oscdimg`/`mkisofs`/etc.
   to build the autounattend CD, none installed. Fix: switched Generation
   2 → 1 and `cd_files` → `floppy_files` — Packer builds floppy images
   natively, no external tool needed, and Windows Setup scans a floppy
   root for `autounattend.xml` the same as a CD root.
3. **File provisioner nested the uploaded scripts one level deep**
   (`environment/scripts/scripts/*.ps1`) because `source = "../scripts"`
   had no trailing slash — Packer's file provisioner copies the source
   *directory itself* into the destination without one. Fixed by adding
   trailing slashes.
4. **Guest OOM during the smoke-test Ghidra import**, twice, with two
   different apparent causes before finding the real one:
   - First: "insufficient memory for the JRE" during `analyzeHeadless`
     with an 8GB VM. Assumed Ghidra's heap auto-detection was too
     aggressive; bumped VM RAM to 16GB — didn't fix it.
   - Second: a *smaller* allocation failure even with 16GB assigned
     (confirmed via `Get-VM | Select MemoryAssigned` — the VM really did
     have 16GB). Root cause: `autounattend.xml`'s own
     `FirstLogonCommands` had set
     `winrm/config/winrs @{MaxMemoryPerShellMB="1024"}` — WinRS enforces
     that as a job-object memory cap on the *entire process tree* spawned
     by the remote shell, including the JVM Ghidra launches as a child
     process. Fixed by setting it to `"0"` (unlimited). VM memory stayed
     at 16GB (harmless, host has 32GB, and real game analysis will want
     the headroom).
5. **`install_ghidra.ps1` silently dropped from `provision.ps1`** during
   an unrelated edit (removing a wrong MAXMEM fix) — caught by noticing
   `config_ghidra.ps1` failed on "Ghidra install not found" and grepping
   the full log for confirmation it never ran that build.

Also: a build survived a real host power/network outage mid-run without
any special handling — Hyper-V VMs and WinRM don't care about the host's
internet connectivity once the VM itself is running locally.

- [x] `environment/scripts/get_packer.ps1` / `install_packer.ps1` — Packer
      1.16.0, portable zip, no admin needed.
- [x] `packer plugins install github.com/hashicorp/hyperv` — installed to
      `%APPDATA%\packer.d`, outside the repo.
- [x] `environment/config.ps1` — Packer, Windows ISO (pinned SHA256), and
      VM-spec params (`$WindowsIsoUrl`, `$VmName`, `$VmCpus`,
      `$VmMemoryMb=16384`, `$VmDiskSizeMb`, `$VmAdminPassword`,
      `$PackerCacheDir`, `$PackerOutputDir`, both on `C:\`) as the single
      source of truth.
- [x] `environment/packer/http/autounattend.xml` — unattended Server 2022
      Standard (Desktop Experience) install, WinRM enabled with no shell
      memory cap. **Known manual sync point:** the Administrator password
      is hardcoded here and must match `$VmAdminPassword` in `config.ps1`
      — no templating wired up yet.
- [x] `environment/packer/windows-server.pkr.hcl` — `hyperv-iso` source,
      Generation 1 + `floppy_files`, `output_directory` on local disk,
      uploads `config.ps1` + `environment/scripts/` +
      `environment/local/scripts/` (trailing slashes!), runs
      `provision.ps1`.
- [x] `environment/packer/scripts/provision.ps1` — guest-side rerun of the
      full Phase 1/1.5 pipeline plus the notepad.exe smoke test, reverting
      config values afterward.
- [x] `environment/local/scripts/build_vm.ps1` — reads `config.ps1`, sets
      `$env:PACKER_CACHE_DIR`, runs `packer init` + `packer build -force`.
- [x] `environment/packer/README.md`.
- [x] Full build run (18m38s once the ISO was cached): succeeded, exit 0.
- [x] Verified the artifact for real: imported a copy of the exported VM
      (`Import-VM -Copy -GenerateNewId`), booted it, used
      `Invoke-Command -VMName` (PowerShell Direct — no network config
      needed) to confirm Ghidra/JDK/Claude Code present on disk and both
      `<INCLUDE CLASS="ghidrassist...">` lines in `_code_browser.tcd`.
      Cleaned up the verification copy afterward.
- [x] **MCP server confirmed fully working inside the built VM.** Rebuilt
      after the post-build changes below, imported, booted. Confirmed
      Ghidra's Project Manager alone does NOT start the MCP server — no
      "GhidrAssist" log lines until a project + CodeBrowser tool is
      actually opened (plugin instantiates per-Tool, not from the
      front-end window). Since PowerShell Direct/WinRM run in Session 0
      (no interactive window station — GUI apps hang there, as seen
      earlier), launching Ghidra needed a scheduled task with
      `schtasks /it` (interactive token) to attach to the autologon'd
      console session (Session 1) instead — confirmed via
      `Get-Process javaw | Select SI` showing session 1, not 0. Opening
      the `.gpr` alone doesn't restore the last-active CodeBrowser
      tool/program either; user double-clicked `notepad.exe` in the VM
      via `vmconnect` for the final step. Log then showed the exact
      same sequence as the dev machine: `MCP Server started on port
      8080` → `Active tool changed: CodeBrowser` → `Program activated:
      notepad.exe`. Port 8080 confirmed open.
- [x] `environment/packer/README.md` now explains *why* build output has
      to be on `C:\` (Google Drive/cloud-sync ACL limitation).
- [ ] Decide whether to keep the built VM as a reusable Hyper-V
      checkpoint/export, or treat `packer build` as the reproducible
      artifact and rebuild on demand.

### Post-build changes (after the first successful build)

- [x] **Folder restructure**, at user's request — the original
      `scripts/` vs `local/scripts/` vs `local/tools/` split (from the
      Phase 1.5 plan wording) read as confusing once there was more in
      it. Flattened: every script (portable `get_*`/`install_*` and the
      machine-oriented ones like `config_ghidra.ps1`, `build_vm.ps1`)
      now lives directly in `environment/scripts/`, fully tracked.
      `environment/local/` is now entirely gitignored machine state —
      `local/tools/` (installed software) and `local/downloads/` (moved
      from `environment/downloads/`) — nothing tracked lives under it.
      Updated: every moved script's relative dot-source paths, the
      `.pkr.hcl` file provisioner (dropped the now-redundant third
      upload block), `provision.ps1`, `.gitignore`, and the README.
- [x] Desktop shortcuts (Ghidra, Claude Code) added to `provision.ps1`,
      on the Public desktop. Also fixed while at it: the native Claude
      Code installer doesn't add `claude.exe` to PATH — `provision.ps1`
      now appends `%USERPROFILE%\.local\bin` to the machine `PATH`.
- [x] Persistent autologon + no lock/sleep, at user's request — the
      unattend `<AutoLogon>` element's `LogonCount` expires after that
      many reboots, so added registry-based autologon
      (`Winlogon\AutoAdminLogon`/`DefaultUserName`/`DefaultPassword`)
      via `FirstLogonCommands`, which doesn't expire. Also disabled the
      screensaver, the "machine inactivity limit" auto-lock policy, and
      display/sleep timeouts (`powercfg`).
- [x] Admin password changed from `ChangeMe123!` to `pass` (found
      `autounattend.xml`'s `AdministratorPassword` already changed to
      `pass` externally, with `AutoLogon.Password` left mismatched at
      `ChangeMe123!` — flagged it rather than guessing, user confirmed
      `pass` was intentional; synced both fields plus `$VmAdminPassword`
      in `config.ps1` plus the new registry autologon commands).
- [x] Rebuilt after all the post-build changes above — succeeded, and
      confirmed for real: restructured paths correct
      (`environment\local\downloads\`, `environment\local\tools\` in
      the build log), desktop shortcuts created, both plugins enabled,
      and — per the MCP confirmation above — the whole toolchain
      actually works inside the freshly-built VM, not just that the
      build script exits 0.

## Phase 3 — Persistent research state (SQLite) — decided

Storage question from the original Phase 3 draft is resolved: SQLite as
the canonical research datastore. Durable, queryable, survives context
resets/VM rebuilds/model changes, copies to another machine and reopens
with zero services running. Raw artifacts (dumps, screenshots, long text)
stay as files on disk, referenced by path from the DB — never blobbed in.

This section was adapted from a ChatGPT-drafted plan the user reviewed
adversarially. Kept: the SQLite decision, the fact/hypothesis/evidence
separation, append-only events, read-only-first safety. Cut, with
reasons, from that draft:
- **No bespoke data-access layer to start.** Claude Code (and any
  subagents) talk to the DB directly via the `sqlite3` CLI —
  `get_sqlite.ps1`/`install_sqlite.ps1`, same download/install pattern as
  every other tool in `environment/scripts/`. Not a PowerShell-only rule
  — Python (or anything else) is fine the moment raw SQL over the CLI
  is actually the wrong tool for something; just don't add the runtime
  before there's a real reason to.
- **5 tables to start, not 10.** Prove one investigation survives a
  context reset before adding structures/relationships/observations/
  decisions/agent_runs tables.
- The draft's Phase 5 (a bespoke "Ghidra tool API": `get_function`,
  `get_xrefs`, `rename_symbol`, etc.) is redundant — GhidrAssistMCP
  (wired up in Phase 1.5) already exposes ~49 tools covering exactly
  this. See the Phase 5 section below.
- The draft's Phases 9/10/15 (specialist agent roster, a distributed
  master/worker model hierarchy, local-model benchmarking) aren't
  adopted as infrastructure to build — see "Agent orchestration
  guidance" below. Claude Code's own subagent dispatch is the default
  until it demonstrably isn't enough.

- [x] `environment/scripts/get_sqlite.ps1` / `install_sqlite.ps1` —
      `sqlite3.exe` CLI, same pattern as every other tool. Tested on the
      dev machine (`sqlite3 -version` works) and wired into
      `provision.ps1` + PATH, baked into the VM build.
- [x] `environment/scripts/get_git.ps1` / `install_git.ps1` — PortableGit
      (self-extracting 7z exe, not a zip — needed `Start-Process -Wait`,
      `& $exe` returns before extraction actually finishes). Not for
      cloning this repo (no remote access from the VM); `provision.ps1`
      runs `git init` + a baseline commit in `C:\fdny-decomp` so the
      agent can track its own changes locally as it runs unattended.
- [x] `environment/packer/http/.gitignore` uploaded to the VM too —
      without it `git add -A` would stage the entire Ghidra/JDK install.
- [x] `SETUP_NOTES.md` — new, separate from `RESEARCH.md`/`plan.md`:
      a short running log of build/infra friction for a human to scan
      before the next `deploy_vm.ps1` run.
- [x] `environment/scripts/deploy_vm.ps1` — one-shot build+import+start+
      verify entry point (elevation check, removes any existing VM,
      runs `build_vm.ps1`, imports the artifact, waits for PowerShell
      Direct, verifies 10 checks including sqlite3/git on PATH). Prompts
      for confirmation before deleting an existing VM that has more than
      the baseline git commit (real accumulated agent work), rather than
      silently destroying it.
- [ ] `environment/config.ps1` — add `$ResearchDbPath` (not done —
      left as the agent's first real task, see the kickoff prompt)
- [ ] Initial schema — 5 tables:
      - `symbols`
      - `hypotheses`
      - `evidence`
      - `research_tasks`
      - `events`
- [ ] Schema principles (non-negotiable, keep from the source draft):
      - facts and hypotheses are different tables — never overwrite a
        hypothesis's history, insert a new row instead
      - every hypothesis row references its evidence row(s); no
        confidence claim without linked evidence
      - confidence is an explicit field, never implied by a record
        merely existing
      - `events` is append-only — the audit log for what changed and why
- [ ] **Prove the loop before doing anything else** — this is the actual
      milestone, not the schema: one Claude Code session investigates a
      single function via GhidrAssistMCP, records an observation +
      hypothesis + evidence in the DB, ends. A fresh session (new
      context window) queries the DB, picks up where it left off, and
      continues. Nothing past this point is worth building until this
      works.

## Phase 4 — Research state, human-readable (deferred)

Not scheduled. `sqlite3 research.db` is enough to answer "what does it
believe / why / what's it uncertain about" while there's barely any
data. Building a viewer now means designing UI for a schema that hasn't
survived contact with reality yet — worth doing once Phase 3 has
stabilized against real use. If/when it happens, use whatever's
actually the right tool — a static HTML page reading the SQLite file
directly, a small Python app, doesn't matter — this repo being
PowerShell-heavy so far isn't a constraint on Phase 4.

## Phase 5 — Ghidra tool interface (mostly already done)

The source draft assumed a bespoke Ghidra tool API needed to be built
from scratch. It doesn't — GhidrAssistMCP already exposes ~49 tools over
MCP (function/xref/string/decompiled-code/disassembly lookups, renames,
type/signature/comment edits, structure creation, etc.), confirmed when
it was wired up in Phase 1.5.

- [ ] Audit GhidrAssistMCP's actual tool list against what research
      tasks actually need — document real gaps, if any, before building
      anything
- [ ] Only if a real gap exists: add it as a Ghidra script (path TBD) —
      don't rebuild what MCP already exposes
- [ ] Safety rule, kept from the source draft: read-only MCP calls by
      default; anything that mutates the Ghidra project (rename,
      retype, comment, structure creation) requires explicit human
      approval before any agent may call it unattended

## Phase 6/7 — Tasks, evidence, hypotheses (folded into Phase 3's schema)

The source draft treated task tracking and the evidence/hypothesis
lifecycle as separate phases with their own elaborate feature lists
(task dependencies/priority/parent-child, a SPECULATION→CONFIRMED state
machine, etc.). Folded into Phase 3 instead — they're properties of the
same five tables, not separate systems. Add columns/states as real
usage demands them (e.g. a `parent_task_id` column when an actual task
needs splitting), not upfront.

## Phase 8 — First research agent

- [ ] **Research the game itself before touching Ghidra.** Identity,
      engine/toolchain, prior art (wikis, existing RE/decomp efforts,
      format docs), a first-pass subsystem map from strings/imports —
      record it in `RESEARCH.md`, including the resulting top-down
      strategy and why. Don't start function-by-function work before
      this exists; it's what turns "poke at random functions" into an
      actual plan.
- [ ] One Claude Code session: GhidrAssistMCP (read-only) + `sqlite3`
      CLI access, given current DB state for one function, a research
      question, and instructions to record findings before ending. No
      multi-agent dispatch yet — this is Phase 3's "prove the loop"
      milestone with a real research question instead of a smoke test.
- [ ] Proposed Ghidra mutations (renames, retypes, comments) get
      written to the DB as a proposal + evidence, not applied directly
      — a human approves before anything mutates the live Ghidra
      project, per Phase 5's safety rule.

### Operating guidance for the agent running on the VM

- You may download and install additional tools as the work demands
  it. Follow the existing convention: a `get_<thing>.ps1` /
  `install_<thing>.ps1` pair in `environment/scripts/`, parameters
  added to `environment/config.ps1` — don't install things by hand
  outside that pattern, or a rebuilt VM won't have them.
- Update `environment/packer/scripts/provision.ps1` (and the `.pkr.hcl`
  if new files need uploading) so anything you added gets baked into
  future builds too — the VM build should stay reproducible from
  scratch, not drift from what's actually installed.
- **Never rebuild the VM.** You run inside it — `packer build` tears
  down and recreates the VM you're running on. Editing the build
  scripts so the *next* build includes your changes is correct;
  triggering that build yourself is not. That's a human decision, from
  the host, when it's actually time to produce a new image.
- **Nothing to research until `$GameExePath` is real.** If it's still
  the placeholder when you start, stop and say so rather than
  inventing work — don't quietly research the notepad.exe smoke-test
  target as if it were the actual goal.
- **Checkpoint constantly, not at the end.** Write findings to
  `RESEARCH.md` (and the Phase 3 DB, once it exists) as you go. An
  overnight/long-running session will hit context resets or
  compaction; anything not written down by then didn't happen. Prefer
  many small writes over one big summary at the end.
- **Timebox stuck work.** If a task isn't yielding progress after a
  reasonable number of attempts, log it as blocked in `RESEARCH.md`
  (what was tried, why it's stuck) and move to a different task rather
  than looping on it indefinitely.
- **Leave a summary for the human.** Whoever reads this next needs one
  place that says what happened, what was found, and what needs a
  judgment call only a person can make — a dedicated section in
  `RESEARCH.md` (e.g. "Needs human attention"), not something scattered
  across session output that's already gone.
- **Don't touch the host or Hyper-V config, and don't do anything
  requiring a reboot, without flagging it first.** Installing a tool
  inside the VM via the established script pattern is fine; anything
  affecting the VM's own OS-level config beyond that needs a human's
  eyes first.
- For a long/overnight run, prefer the `/loop` skill (self-pacing,
  survives long stretches better) over one continuous unbroken session.

## Agent orchestration guidance

Per user request: heavy reasoning for big/strategic work, lightweight
agents for small mechanical work. This is Claude Code's own `Agent`
tool (`subagent_type`, `model` override) — not custom multi-model
infrastructure:

- **Strategic work** — deciding what to investigate next, resolving
  conflicting evidence, judging a hypothesis confirmed, synthesizing
  across many findings — stays with the primary session, or an explicit
  high-effort/`opus` agent for a specific hard sub-problem. This plays
  the role of the source draft's "master" model, but it's a
  model-selection choice, not a service to build.
- **Mechanical work** — "call GhidrAssistMCP's `get_xrefs` for
  `FUN_80123456` and report the raw results," "look up this string's
  references," anything with a narrow, well-defined output — goes to a
  lightweight subagent (`Agent` tool, default/cheap model, or a `fork`
  when it needs the parent's conversation context). Don't spend a
  high-effort model's budget on a single MCP tool call.
- Do not build the source draft's specialist-agent roster or a
  distributed master/worker model hierarchy as infrastructure. If
  Claude Code's native subagent dispatch turns out to be insufficient,
  that's a failure mode to observe first — build the custom version
  only after hitting a concrete wall, not speculatively.

## Future direction (unscheduled, not designed yet)

From the source draft, kept as pointers only — deliberately not
fleshed into checklists, because doing that now is the premature-
architecture problem the draft's own closing note warned against
("the architecture should evolve from observed failure modes rather
than being fully designed upfront"):

- Long-running/autonomous research (queueing, parallel workers,
  scheduled research)
- Autonomous mutation with rollback, once the approval-gated version
  has run long enough to trust
- Runtime/debugger analysis correlated with static findings
- Richer knowledge visualization (graphs)
- Local model / hardware evaluation, if cost or latency ever actually
  becomes a problem
- Dedicated server deployment, separate from the dev/analysis VM

None of these are scoped, and shouldn't be until Phase 3 and Phase 8
have actually run against the real game and produced a concrete reason
to build the next piece.
