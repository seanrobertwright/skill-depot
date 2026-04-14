# Skill Depot

A one-command, project-scoped installer for Claude Code skills.

`skill-depot` lets developers drop skills into any project without manual cloning, copying, or wiring — scoped to that project so the global skill namespace stays clean.

## Status

Early scaffolding. PRD complete — see `docs/prd.md`. Implementation gated on a validation spike (Phase 0).

## Usage (planned)

```bash
# Install a skill into the current project (from registry short name)
skill-depot add <skill-name>

# Install directly from a GitHub URL
skill-depot add <github-url>

# List skills installed in the current project
skill-depot list

# Remove a skill from the current project
skill-depot remove <skill-name>
```

Skills install into `.claude/skills/` relative to the current project — not globally.
