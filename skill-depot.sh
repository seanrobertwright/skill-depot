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
  skill-depot update [skill-name]   Update skill(s) to latest version
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

validate_subdir() {
  local subdir="$1" repo_root="$2"
  # Reject dangerous syntax early (absolute, traversal, double-separator)
  case "$subdir" in
    /*|"."|".."|*//*|./*|../*|*/./*|*/../*|*/.|*/..)
      return 1 ;;
  esac
  [[ -d "$repo_root/$subdir" ]] || return 1
  # Canonicalize and ensure it stays under the repo root
  local resolved_root resolved_source
  resolved_root="$(cd "$repo_root" && pwd -P)"
  resolved_source="$(cd "$repo_root/$subdir" && pwd -P)"
  [[ "$resolved_source" == "$resolved_root"/* ]]
}

cmd_add() {
  local input="${1:-}"
  if [[ -z "$input" ]]; then
    echo "Usage: skill-depot add <skill-name|github-url>"
    return 1
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
      return 1
    fi
    if [[ ! -f "$REGISTRY_FILE" ]]; then
      echo "Error: registry file not found at ${REGISTRY_FILE}"
      return 1
    fi
    local entry
    entry=$(grep -E "^  ${name}:" "$REGISTRY_FILE" | head -1 | sed 's/^[[:space:]]*[^:]*:[[:space:]]*//' || true)
    if [[ -z "$entry" ]]; then
      echo "Error: skill '${name}' not found in registry."
      echo "Try: skill-depot add <github-url> to install directly."
      return 1
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
    return 1
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
  local tmp staging_parent staged_target
  tmp="$(mktemp -d)"
  staging_parent="$(mktemp -d)"
  staged_target="${staging_parent}/${name}"
  trap 'rm -rf "${tmp:-}" "${staging_parent:-}"' RETURN

  echo "Installing skill '${name}'..."
  if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --quiet "$url" "$tmp/repo"; then
    echo "Error: failed to clone ${url}"
    return 1
  fi

  # Extract skill (subdirectory or whole repo)
  if [[ -n "$subdir" ]]; then
    if ! validate_subdir "$subdir" "$tmp/repo"; then
      echo "Error: invalid or missing subdirectory '${subdir}' in ${url}"
      return 1
    fi
    local source_path
    source_path="$(cd "$tmp/repo/$subdir" && pwd -P)"
    cp -r "$source_path" "$staged_target"
  else
    # Copy whole repo, excluding .git
    mkdir -p "$staged_target"
    (cd "$tmp/repo" && find . -maxdepth 1 ! -name . ! -name .git -exec cp -r {} "$staged_target/" \;)
  fi

  mv "$staged_target" "$target"

  # Write origin metadata for update support
  local commit_hash
  commit_hash=$(git -C "$tmp/repo" rev-parse HEAD)
  cat > "$target/.skill-depot-origin" <<ORIGIN
url=${url}
subdir=${subdir}
commit=${commit_hash}
ORIGIN

  # Verify SKILL.md exists
  if [[ ! -f "$target/SKILL.md" ]]; then
    echo "Warning: ${target}/SKILL.md not found. Claude Code requires SKILL.md to load skills."
  fi

  echo "Installed skill '${name}' to ${target}/."
}

cmd_update() {
  local input="${1:-}"

  # Collect skills to update
  local skills_to_update=()

  if [[ -n "$input" ]]; then
    # Single skill update
    if [[ ! "$input" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "Error: invalid skill name '${input}'. Names must contain only letters, numbers, hyphens, and underscores."
      return 1
    fi
    if [[ ! -d "${SKILLS_DIR}/${input}" ]]; then
      echo "Error: skill '${input}' is not installed in ${SKILLS_DIR}/."
      return 1
    fi
    skills_to_update+=("$input")
  else
    # Update all installed skills
    if [[ ! -d "$SKILLS_DIR" ]]; then
      echo "No skills installed to update."
      return 0
    fi
    for dir in "$SKILLS_DIR"/*/; do
      [[ -d "$dir" ]] || continue
      skills_to_update+=("$(basename "$dir")")
    done
    if [[ ${#skills_to_update[@]} -eq 0 ]]; then
      echo "No skills installed to update."
      return 0
    fi
  fi

  local updated=0 up_to_date=0

  for name in "${skills_to_update[@]}"; do
    local target="${SKILLS_DIR}/${name}"
    local origin_file="${target}/.skill-depot-origin"

    # Check for origin metadata
    if [[ ! -f "$origin_file" ]]; then
      echo "Error: skill '${name}' has no origin metadata. Remove and re-add it: skill-depot remove ${name} && skill-depot add ${name}"
      return 1
    fi

    # Read origin metadata
    local orig_url orig_subdir orig_commit
    orig_url=$(grep '^url=' "$origin_file" | cut -d= -f2-)
    orig_subdir=$(grep '^subdir=' "$origin_file" | cut -d= -f2-)
    orig_commit=$(grep '^commit=' "$origin_file" | cut -d= -f2-)

    # Check latest remote commit
    local remote_commit
    remote_commit=$(GIT_TERMINAL_PROMPT=0 git ls-remote "$orig_url" HEAD 2>/dev/null | awk '{print $1}') || true
    if [[ -z "$remote_commit" ]]; then
      echo "Error: cannot reach ${orig_url}"
      return 1
    fi

    # Compare commits
    if [[ "$remote_commit" == "$orig_commit" ]]; then
      echo "Skill '${name}' is already up to date."
      up_to_date=$((up_to_date + 1))
      continue
    fi

    # Clone fresh copy
    local tmp staging_parent staged_target
    tmp="$(mktemp -d)"
    staging_parent="$(mktemp -d)"
    staged_target="${staging_parent}/${name}"
    trap 'rm -rf "${tmp:-}" "${staging_parent:-}"' RETURN

    echo "Updating skill '${name}'..."
    if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --quiet "$orig_url" "$tmp/repo"; then
      echo "Error: failed to clone ${orig_url}"
      return 1
    fi

    # Extract skill (subdirectory or whole repo)
    if [[ -n "$orig_subdir" ]]; then
      if ! validate_subdir "$orig_subdir" "$tmp/repo"; then
        echo "Error: invalid or missing subdirectory '${orig_subdir}' in origin metadata for '${name}'"
        return 1
      fi
      local source_path
      source_path="$(cd "$tmp/repo/$orig_subdir" && pwd -P)"
      cp -r "$source_path" "$staged_target"
    else
      mkdir -p "$staged_target"
      (cd "$tmp/repo" && find . -maxdepth 1 ! -name . ! -name .git -exec cp -r {} "$staged_target/" \;)
    fi

    # Non-atomic replace — skill dir is briefly absent between rm and mv
    rm -rf "$target"
    mv "$staged_target" "$target"

    # Write updated origin metadata
    local commit_hash
    commit_hash=$(git -C "$tmp/repo" rev-parse HEAD)
    cat > "$target/.skill-depot-origin" <<ORIGIN
url=${orig_url}
subdir=${orig_subdir}
commit=${commit_hash}
ORIGIN

    # Cleanup temp dirs
    rm -rf "${tmp:-}" "${staging_parent:-}"

    echo "Updated skill '${name}'."
    updated=$((updated + 1))
  done

  # Summary for update-all
  if [[ -z "$input" ]] && [[ $((updated + up_to_date)) -gt 1 ]]; then
    echo ""
    echo "Update summary: ${updated} updated, ${up_to_date} already up to date."
  fi
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    add)    cmd_add "$@" ;;
    list)   cmd_list "$@" ;;
    remove) cmd_remove "$@" ;;
    update) cmd_update "$@" ;;
    -h|--help|help) usage ;;
    -v|--version) echo "skill-depot $VERSION" ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
