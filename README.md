# Skill Depot

A one-command, project-scoped installer for Claude Code skills.

`skill-depot` lets developers drop skills into any project without manual cloning, copying, or wiring — scoped to that project so the global skill namespace stays clean.

## Quick Start

```bash
# Clone this repo (or download skill-depot.sh)
git clone https://github.com/seanrobertwright/skill-depot.git
cd skill-depot

# Install a skill into your project by short name
./skill-depot.sh add pdf

# Or install directly from a GitHub URL
./skill-depot.sh add https://github.com/anthropics/skills#skills/claude-api

# List installed skills
./skill-depot.sh list

# Remove a skill
./skill-depot.sh remove pdf
```

## Usage

```bash
skill-depot add <skill-name>      # Install skill from registry
skill-depot add <github-url>      # Install skill from GitHub URL
skill-depot list                  # List installed skills
skill-depot remove <skill-name>   # Remove an installed skill
skill-depot help                  # Show this help
skill-depot --version             # Show version
```

Skills install into `.claude/skills/` relative to the current directory — not globally.

## Registry

The built-in `registry.yaml` maps short names to GitHub skill URLs. Available skills:

| Name | Source |
|------|--------|
| claude-api | anthropics/skills |
| pdf | anthropics/skills |
| skill-creator | anthropics/skills |
| mcp-builder | anthropics/skills |
| frontend-design | anthropics/skills |
| webapp-testing | anthropics/skills |
| docx | anthropics/skills |
| xlsx | anthropics/skills |
| pptx | anthropics/skills |

You can also install any skill directly from a GitHub URL — no registry entry required.

## URL Format

Skill Depot supports two URL patterns:

- **Full repo**: `https://github.com/owner/repo` — clones the entire repo as one skill
- **Subdirectory**: `https://github.com/owner/repo#path/to/skill` — extracts a specific subdirectory from a monorepo

## Requirements

- `bash` >= 3.2
- `git`

## Status

Phase 0 (validation) and Phase 1 (MVP) complete. See `docs/prd.md` for roadmap.
