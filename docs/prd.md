# Skill Depot — Product Requirements Document

**Status:** Phase 1 Complete  
**Date:** 2026-04-14  
**Author:** Generated via PRD session

---

## 1. Problem Statement

**Who is affected:** Developers using Claude Code who are setting up new projects or working across multiple projects.

**What breaks:** As developers accumulate skills globally (`~/.claude/skills/`), the global skill set grows unmanaged. Skills overlap, contradict each other, and confuse the AI agent. The agent receives contradictory instructions from multiple global skills and produces degraded, inconsistent output. There is no tooling for scoping skills per-project vs. globally — users default to global installs because it is easier, which compounds the problem.

**Why it hurts today:** Installing a skill requires cloning repos, copying directories, manually managing versions, and deciding which skills belong to which project — all with no tooling support. The friction of per-project installs means everyone defaults to global, causing the sprawl problem to worsen with every new skill published.

---

## 2. Evidence

- Skills adoption is accelerating. More developers are writing and sharing skills, growing the ecosystem rapidly.
- Management tooling has not kept pace with skill publishing. Discovery and installation remain entirely manual.
- The pain of global skill sprawl compounds with each new skill added — the more popular skills become, the worse the conflict problem gets.
- The primary workaround today (global install everything) directly causes the problem Skill Depot is designed to solve.

---

## 3. Proposed Solution

**Skill Depot** is a project-scoped skill manager delivered as a single bash script. It gives developers one command to install a named skill into the current project's `.claude/skills/` directory — scoped to that project, not globally.

```
skill-depot add <skill-name>        # install from registry by short name
skill-depot add <github-url>        # install directly from a GitHub URL
skill-depot list                    # show skills installed in current project
skill-depot remove <skill-name>     # clean uninstall from current project
```

Skills install into `.claude/skills/` relative to the current working directory. This keeps skills scoped to the project and avoids polluting the global namespace.

The product identity is **Skill Depot** — not `skills.sh`. It may integrate with or complement the skills.sh ecosystem but is its own product with its own identity focused on project-scoped management.

---

## 4. Key Hypothesis

> A one-command project-scoped install will eliminate the global skill sprawl problem for developers starting new projects.

**We will know we are right when:** Users who previously installed all skills globally begin using per-project installs and report fewer AI confusion issues. The leading indicator is adoption of `skill-depot add` over manual global installs.

---

## 5. What We're NOT Building

| Out of Scope | Reason |
|---|---|
| Web marketplace or UI | Adds scope without validating core install mechanic |
| Skill authoring tools | Different user and different job-to-be-done |
| Global skill management | Explicitly out of scope — project scope is the thesis |
| Conflict detection | Can wait until basic install is validated |
| Versioning / update command | Can wait — pin-at-install is sufficient for v1 |
| Publishing tools | Out of scope — this is a consumer tool, not a publisher tool |
| MCP server bundles | Not skills — different primitive |
| Hook bundles | Not skills — different primitive |
| Plugin system compatibility | Out of scope for v1 |

---

## 6. Success Metrics

| Metric | Target | Notes |
|---|---|---|
| Install friction | One command installs a skill end-to-end | Primary UX bar |
| Discoverability | User can find and install a skill by short name | Requires a minimal registry |
| Visibility | `skill-depot list` shows all skills in current project | Must be accurate |
| Clean removal | `skill-depot remove` leaves no artifacts | No dangling files |
| AI confusion reduction | Users report fewer conflicting-instruction issues | Qualitative, v1 signal |
| Adoption shift | New projects use per-project install instead of global | Leading indicator of thesis validation |

---

## 7. Open Questions

| Question | Priority | Resolution Path |
|---|---|---|
| **Does Claude Code load `.claude/skills/` at the project level?** | **BLOCKING** | 30-minute spike: create a `.claude/skills/` dir in a test project, add a skill, and verify Claude Code picks it up. This must be confirmed before committing to the install-to-`.claude/skills/` architecture. This spike is the first task. |
| What is the canonical source for a skills registry? | High | Determine if skills.sh has a registry API or if a static YAML/JSON manifest in the skill-depot repo is the right approach for v1 |
| How should installs handle subdirectory structure within a skill repo? | Medium | Does a skill repo contain exactly one skill, or multiple? Need to define what "a skill" is structurally |
| Authentication for private skill repos | Low | GitHub personal access tokens sufficient for v1? Or defer entirely? |

---

## 8. Users & Context

### Primary User

Any developer building with an AI CLI that uses skills who does not have time to manually install and manage them. They want to get started fast without friction. They are comfortable with the terminal but do not want to manage git clones and directory copies by hand.

### Job To Be Done

> When creating a new project (or modifying an existing one), I want to add my favorite skills, so I can build effectively with the right AI behavior scoped to this project.

### Non-Users

Anyone who is not a developer. This is a developer tool. Non-technical users, product managers, and designers are explicitly not the audience.

---

## 9. Solution Detail

### MVP Definition

A single bash script `skill-depot.sh` (or installed as `skill-depot`) that executes:

```bash
skill-depot add <github-url>
```

Clones the skill repo into `.claude/skills/<skill-name>/` in the current working directory. Validates that Claude Code picks it up (dependent on spike in Open Questions).

### MoSCoW — v1

| Priority | Feature | Notes |
|---|---|---|
| **Must** | `add` from a GitHub URL | Core install mechanic |
| **Must** | `add` from registry by short name | Requires minimal registry (static manifest acceptable) |
| **Must** | `list` — show installed skills in current project | Read `.claude/skills/` dir |
| **Must** | `remove` — clean uninstall | Delete `.claude/skills/<name>/`, leave nothing behind |
| **Should** | Idempotent installs | Re-running `add` on an already-installed skill should not error or duplicate |
| **Should** | Helpful error messages | Clear output when GitHub URL is invalid, skill not found, etc. |
| **Could** | `update` command | Refresh an installed skill to latest | 
| **Could** | Conflict detection | Warn when two installed skills have overlapping command names |
| **Won't** | Versioning / pinning | Defer post-v1 |
| **Won't** | Web UI | Out of scope |

---

## 10. Technical Approach

### Codebase State (updated 2026-04-14)

Phase 1 implementation is complete. The repository contains:

```
skill-depot/
├── .archon/
│   ├── commands/
│   ├── workflows/
│   └── config.yaml
├── docs/
│   └── prd.md
├── tests/
│   └── e2e-test.sh
├── skill-depot.sh        # Main script — all commands implemented
├── registry.yaml         # Static registry with skill short names
├── .gitignore
└── README.md
```

### Architecture Decision

Install target: `.claude/skills/<skill-name>/` relative to `$PWD`.

**Confirmed:** Claude Code loads project-level `.claude/skills/<skill-name>/SKILL.md` automatically. See Open Questions #1.

### Files to Create

| File | Purpose |
|---|---|
| `skill-depot.sh` | Main script — entry point for all commands |
| `registry.yaml` | Static manifest mapping short names to GitHub URLs (v1 registry) |
| `.claude/skills/` | Created at install time in the target project (not in this repo) |

### `skill-depot.sh` — Command Structure (implemented)

```bash
#!/usr/bin/env bash
set -euo pipefail

SKILLS_DIR=".claude/skills"

cmd_add()    { ... }   # clone into $SKILLS_DIR/<name>/
cmd_list()   { ... }   # ls $SKILLS_DIR/
cmd_remove() { ... }   # rm -rf $SKILLS_DIR/<name>/
```

### Registry Design (v1)

A static `registry.yaml` in the skill-depot repo maps short names to GitHub clone URLs. This is the simplest approach that validates the install mechanic without building a registry service.

```yaml
skills:
  pdf: https://github.com/anthropics/skills#skills/pdf
  commit: https://github.com/anthropics/skills#skills/commit
  # URL#subdir fragment syntax for monorepo skill sources
```

### Dependencies

- `git` — required for clone-based install
- `bash` ≥ 3.2 — for cross-platform compatibility (macOS ships bash 3.2)
- No other runtime dependencies by design

### Spike: Project-Level Skill Loading (BLOCKING)

**Task:** Manually verify that Claude Code loads skills from `.claude/skills/` at the project level, not just from `~/.claude/skills/`.

**Steps:**
1. In a scratch directory, create `.claude/skills/test-skill/`
2. Add a minimal skill definition file (check Claude Code skill format)
3. Open Claude Code in that directory
4. Confirm the skill is available and active

**Time-box:** 30 minutes.  
**If it works:** Proceed with `.claude/skills/` as the install target.  
**If it does not work:** Re-evaluate install target — may need to inject into a config file or use a different mechanism. Do not proceed with implementation until this is resolved.

---

## 11. Implementation Phases

### Phase 0 — Validation Spike (before any code)

| Task | Owner | Status |
|---|---|---|
| Verify Claude Code loads project-level `.claude/skills/` | Docs research | Complete |

**Gate:** Phase 1 does not begin until Phase 0 is confirmed.

**Resolution:** Official Claude Code docs confirm project-level `.claude/skills/<skill-name>/SKILL.md` is auto-discovered. Skills committed to version control are encouraged. No manual spike needed.

**Plan:** `artifacts/runs/4f873bd1fc0049f9768c7876c7d66e08/plan.md`

### Phase 1 — MVP (post-spike)

| Task | Parallel? | Status |
|---|---|---|
| Write `skill-depot.sh` with `add <github-url>` | No — blocked on spike | Complete |
| Write `skill-depot.sh list` command | Yes — alongside add | Complete |
| Write `skill-depot.sh remove` command | Yes — alongside add | Complete |
| Create initial `registry.yaml` (5–10 known skills) | Yes — parallel to script | Complete |
| End-to-end test: install a real skill, verify Claude Code uses it | No — after all above | Complete |

**Plan:** `artifacts/runs/4f873bd1fc0049f9768c7876c7d66e08/plan.md`

### Phase 2 — Registry & Short Names

| Task | Parallel? | Status |
|---|---|---|
| Wire `skill-depot add <short-name>` to registry lookup | No | Complete |
| Expand registry to cover common skills | Yes | Complete |
| Idempotent install behavior | Yes | Complete |

### Phase 3 — Polish (post-validation)

| Task | Parallel? | Status |
|---|---|---|
| Error handling and user-facing messages | Yes | Not started |
| `update` command | Yes | Not started |
| Conflict detection (overlapping command names) | Yes | Not started |

---

## 12. Decisions Log

| Decision | Rationale | Date |
|---|---|---|
| Product name is **Skill Depot**, not skills.sh | Distinct identity; may complement skills.sh ecosystem but is its own product | 2026-04-14 |
| Bash script as delivery mechanism | No runtime dependencies; universal for macOS/Linux devs; matches target user's environment | 2026-04-14 |
| Install target is `.claude/skills/` (project-local) | Core thesis: project-scoped installs prevent global sprawl. **Pending spike validation.** | 2026-04-14 |
| Static `registry.yaml` for v1 registry | Simplest approach that validates the install mechanic; no registry service needed for v1 | 2026-04-14 |
| No versioning in v1 | Adds complexity without validating the core hypothesis first | 2026-04-14 |
| No conflict detection in v1 | Same rationale — validate install before adding guardrails | 2026-04-14 |
| No web UI, no publishing tools | Out of scope; different users and different jobs-to-be-done | 2026-04-14 |
| Spike is first task, phases are gated on it | Architecture depends on unverified behavior of Claude Code; do not build on unconfirmed foundation | 2026-04-14 |

---

## Validation Notes

Validated against codebase at `D:/repos/skill-depot` (worktree `archon/task-prd-skills-sh`) on 2026-04-14.

**File paths (5 checked):**
- `.archon/config.yaml` ✅ — confirmed: `assistant: claude`, `worktree.baseBranch: main`
- `.archon/commands/` ✅ — exists, empty (.gitkeep only)
- `.archon/workflows/` ✅ — exists, empty (.gitkeep only)
- `.gitignore` ✅ — exists
- `README.md` ✅ — exists, documents planned commands only, no implementation

**API endpoints:** N/A — CLI tool, no web server.

**DB schemas:** N/A — no database.

**UI components:** N/A — CLI tool.

**Corrections made: 0**

**Discrepancies noted (not PRD errors — upstream issues):**

1. `README.md` line 1 contains a typo: heading reads `# Skill Deport` instead of `# Skill Depot`. PRD is correct. README should be fixed before implementation begins.

2. `README.md` references `./skills.sh` as the script name throughout. PRD correctly uses `skill-depot.sh` per the naming decision made during the PRD session. README predates this decision and will need to be updated.

3. Registry YAML example URLs (`https://github.com/anthropics/skills/commit`) are illustrative only and already self-flagged as "Needs verification" in the PRD. Not a PRD error.
