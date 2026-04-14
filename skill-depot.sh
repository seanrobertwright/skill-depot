#!/usr/bin/env bash
set -euo pipefail

# Skill Depot — project-scoped skill manager for Claude Code
VERSION="0.1.0"
SKILLS_DIR=".claude/skills"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_FILE="${SCRIPT_DIR}/registry.yaml"

usage() {
  cat <<EOF
skill-depot v${VERSION} — project-scoped skill manager for Claude Code

Usage:
  skill-depot add <skill-name>      Install skill from registry
  skill-depot add <github-url>      Install skill from GitHub URL
  skill-depot list                  List installed skills
  skill-depot remove <skill-name>   Remove an installed skill
  skill-depot help                  Show this help
  skill-depot --version             Show version

Skills install into .claude/skills/ relative to the current directory.
EOF
}

cmd_list() {
  if [[ ! -d "$SKILLS_DIR" ]]; then
    echo "No skills installed (${SKILLS_DIR}/ does not exist)."
    return 0
  fi

  local skills=()
  for dir in "$SKILLS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    local name
    name="$(basename "$dir")"
    skills+=("$name")
  done

  if [[ ${#skills[@]} -eq 0 ]]; then
    echo "No skills installed in ${SKILLS_DIR}/."
    return 0
  fi

  echo "Installed skills (${SKILLS_DIR}/):"
  for s in "${skills[@]}"; do
    local desc=""
    if [[ -f "${SKILLS_DIR}/${s}/SKILL.md" ]]; then
      desc=$(grep -m1 '^description:' "${SKILLS_DIR}/${s}/SKILL.md" | sed 's/^description:[[:space:]]*//' || true)
    fi
    if [[ -n "$desc" ]]; then
      printf "  %-20s %s\n" "$s" "$desc"
    else
      echo "  $s"
    fi
  done
}

cmd_remove() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    echo "Usage: skill-depot remove <skill-name>"
    exit 1
  fi

  # Validate skill name to prevent path traversal
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: invalid skill name '${name}'. Names must contain only letters, numbers, hyphens, and underscores."
    exit 1
  fi

  local target="${SKILLS_DIR}/${name}"
  if [[ ! -d "$target" ]]; then
    echo "Error: skill '${name}' is not installed in ${SKILLS_DIR}/."
    exit 1
  fi

  rm -rf "$target"
  echo "Removed skill '${name}' from ${SKILLS_DIR}/."

  # Clean up empty .claude/skills/ directory
  if [[ -d "$SKILLS_DIR" ]] && [[ -z "$(ls -A "$SKILLS_DIR")" ]]; then
    rmdir "$SKILLS_DIR"
  fi
}

cmd_add() {
  local input="${1:-}"
  if [[ -z "$input" ]]; then
    echo "Usage: skill-depot add <skill-name|github-url>"
    exit 1
  fi

  local url="" name="" subdir=""

  if [[ "$input" =~ ^https?:// ]] || [[ "$input" =~ ^git@ ]]; then
    # Direct URL — parse name from URL, handle #subdir fragment
    url="$input"
    if [[ "$url" == *"#"* ]]; then
      subdir="${url##*#}"
      url="${url%%#*}"
    fi
    if [[ -n "$subdir" ]]; then
      name="$(basename "$subdir")"
    else
      name="$(basename "$url" .git)"
    fi
  else
    # Short name — look up in registry
    name="$input"
    # Validate skill name to prevent path traversal
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "Error: invalid skill name '${name}'. Names must contain only letters, numbers, hyphens, and underscores."
      exit 1
    fi
    if [[ ! -f "$REGISTRY_FILE" ]]; then
      echo "Error: registry file not found at ${REGISTRY_FILE}"
      exit 1
    fi
    local entry
    entry=$(grep -E "^  ${name}:" "$REGISTRY_FILE" | head -1 | sed 's/^[[:space:]]*[^:]*:[[:space:]]*//' || true)
    if [[ -z "$entry" ]]; then
      echo "Error: skill '${name}' not found in registry."
      echo "Try: skill-depot add <github-url> to install directly."
      exit 1
    fi
    url="$entry"
    if [[ "$url" == *"#"* ]]; then
      subdir="${url##*#}"
      url="${url%%#*}"
    fi
  fi

  # Validate skill name to prevent path traversal
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: invalid skill name '${name}'. Names must contain only letters, numbers, hyphens, and underscores."
    exit 1
  fi

  local target="${SKILLS_DIR}/${name}"

  # Idempotent: skip if already installed
  if [[ -d "$target" ]]; then
    echo "Skill '${name}' is already installed at ${target}/."
    echo "To reinstall, remove it first: skill-depot remove ${name}"
    return 0
  fi

  # Clone
  mkdir -p "$SKILLS_DIR"
  local tmp
  tmp="$(mktemp -d)"

  echo "Installing skill '${name}'..."
  if ! git clone --depth 1 --quiet "$url" "$tmp/repo"; then
    rm -rf "$tmp"
    echo "Error: failed to clone ${url}"
    exit 1
  fi

  # Extract skill (subdirectory or whole repo)
  if [[ -n "$subdir" ]]; then
    if [[ ! -d "$tmp/repo/$subdir" ]]; then
      rm -rf "$tmp"
      echo "Error: subdirectory '${subdir}' not found in ${url}"
      exit 1
    fi
    cp -r "$tmp/repo/$subdir" "$target"
  else
    # Copy whole repo, excluding .git
    mkdir -p "$target"
    (cd "$tmp/repo" && find . -maxdepth 1 ! -name . ! -name .git -exec cp -r {} "$target/" \;)
  fi

  rm -rf "$tmp"

  # Verify SKILL.md exists
  if [[ ! -f "$target/SKILL.md" ]]; then
    echo "Warning: ${target}/SKILL.md not found. Claude Code requires SKILL.md to load skills."
  fi

  echo "Installed skill '${name}' to ${target}/."
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    add)    cmd_add "$@" ;;
    list)   cmd_list "$@" ;;
    remove) cmd_remove "$@" ;;
    -h|--help|help) usage ;;
    -v|--version) echo "skill-depot $VERSION" ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
