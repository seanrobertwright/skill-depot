#!/usr/bin/env bash
set -euo pipefail

# E2E test for skill-depot
# Runs in a temp directory to avoid polluting the project

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DEPOT="${SCRIPT_DIR}/skill-depot.sh"
PASS=0
FAIL=0
NETWORK_OK=1

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — file not found: $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_not_exists() {
  local desc="$1" path="$2"
  if [[ ! -d "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — directory still exists: $path"
    FAIL=$((FAIL + 1))
  fi
}

# Setup temp directory
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

# Keep this short so CI/offline runs skip quickly instead of hanging on network checks.
if ! GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=3 ls-remote --exit-code https://github.com/anthropics/skills >/dev/null 2>&1; then
  NETWORK_OK=0
fi

echo "=== Skill Depot E2E Tests ==="
echo "Working directory: $TMPDIR"
echo ""

# Test 1: Help
echo "Test: help command"
output=$(bash "$SKILL_DEPOT" help 2>&1)
assert_contains "help shows usage" "skill-depot" "$output"

# Test 2: Version
echo "Test: version command"
output=$(bash "$SKILL_DEPOT" --version 2>&1)
assert_contains "version output" "skill-depot" "$output"

# Test 3: List with no skills
echo "Test: list with no skills installed"
output=$(bash "$SKILL_DEPOT" list 2>&1)
assert_contains "list shows no skills" "No skills" "$output"

# Test 4: Add from GitHub URL (using a real skill from anthropics/skills)
echo "Test: add from GitHub URL"
if [[ $NETWORK_OK -eq 1 ]]; then
  bash "$SKILL_DEPOT" add https://github.com/anthropics/skills#skills/pdf
  assert_file_exists "SKILL.md exists after add" ".claude/skills/pdf/SKILL.md"
else
  echo "  SKIP: network unavailable; skipping GitHub-backed tests"
fi

# Test 5: List shows installed skill
echo "Test: list shows installed skill"
output=$(bash "$SKILL_DEPOT" list 2>&1)
if [[ $NETWORK_OK -eq 1 ]]; then
  assert_contains "list shows pdf skill" "pdf" "$output"
else
  assert_contains "list still works with no skills" "No skills" "$output"
fi

# Test 6: Idempotent add
echo "Test: idempotent add"
if [[ $NETWORK_OK -eq 1 ]]; then
  output=$(bash "$SKILL_DEPOT" add https://github.com/anthropics/skills#skills/pdf 2>&1)
  assert_contains "idempotent message" "already installed" "$output"
else
  echo "  SKIP: idempotent network install test"
fi

# Test 7: Remove (and empty-dir cleanup)
echo "Test: remove skill"
if [[ $NETWORK_OK -eq 1 ]]; then
  bash "$SKILL_DEPOT" remove pdf
  assert_dir_not_exists "skill dir removed" ".claude/skills/pdf"
  # When the last skill is removed, .claude/skills/ should also be cleaned up
  # so repos don't end up with stray empty dirs in their tree.
  assert_dir_not_exists "empty .claude/skills dir cleaned up" ".claude/skills"
else
  echo "  SKIP: remove network-installed skill test"
fi

# Test 8: Remove nonexistent skill fails
echo "Test: remove nonexistent skill"
if output=$(bash "$SKILL_DEPOT" remove nonexistent 2>&1); then
  echo "  FAIL: should have exited non-zero"
  FAIL=$((FAIL + 1))
else
  assert_contains "error message for missing skill" "not installed" "$output"
fi

# Test 9: Add from registry short name
echo "Test: add from registry short name"
if [[ $NETWORK_OK -eq 1 ]]; then
  bash "$SKILL_DEPOT" add pdf
  assert_file_exists "SKILL.md from registry add" ".claude/skills/pdf/SKILL.md"
else
  echo "  SKIP: registry-backed add test"
fi

# Cleanup for next test
if [[ $NETWORK_OK -eq 1 ]]; then
  bash "$SKILL_DEPOT" remove pdf
fi

# Test 10: Add with invalid GitHub URL (clone failure)
echo "Test: add with invalid URL"
if [[ $NETWORK_OK -eq 1 ]]; then
  if output=$(bash "$SKILL_DEPOT" add https://github.com/nonexistent/repo-does-not-exist-xyz 2>&1); then
    echo "  FAIL: should have exited non-zero"
    FAIL=$((FAIL + 1))
  else
    assert_contains "error message for bad URL" "failed to clone" "$output"
  fi
else
  echo "  SKIP: invalid URL clone test"
fi

# Test 11: Add with unknown registry name
echo "Test: add with unknown registry name"
if output=$(bash "$SKILL_DEPOT" add nonexistent-skill-xyz 2>&1); then
  echo "  FAIL: should have exited non-zero"
  FAIL=$((FAIL + 1))
else
  assert_contains "error for unknown skill" "not found in registry" "$output"
fi

# Test 12: Add with invalid skill name (path traversal)
echo "Test: add with invalid skill name"
if output=$(bash "$SKILL_DEPOT" add "../../etc" 2>&1); then
  echo "  FAIL: should have exited non-zero"
  FAIL=$((FAIL + 1))
else
  assert_contains "error for invalid name" "invalid skill name" "$output"
fi

# Test 13: Remove with invalid skill name (path traversal)
echo "Test: remove with invalid skill name"
if output=$(bash "$SKILL_DEPOT" remove "../.git" 2>&1); then
  echo "  FAIL: should have exited non-zero"
  FAIL=$((FAIL + 1))
else
  assert_contains "error for invalid remove name" "invalid skill name" "$output"
fi

# Summary
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
