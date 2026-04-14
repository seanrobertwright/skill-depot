#!/usr/bin/env bash
set -euo pipefail

# E2E test for skill-depot
# Runs in a temp directory to avoid polluting the project

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DEPOT="${SCRIPT_DIR}/skill-depot.sh"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

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

echo "=== Skill Depot E2E Tests ==="
echo "Working directory: $TMPDIR"
echo ""

# Test 1: Help
echo "Test: help command"
output=$("$SKILL_DEPOT" help 2>&1)
assert_contains "help shows usage" "skill-depot" "$output"

# Test 2: Version
echo "Test: version command"
output=$("$SKILL_DEPOT" --version 2>&1)
assert_contains "version output" "skill-depot" "$output"

# Test 3: List with no skills
echo "Test: list with no skills installed"
output=$("$SKILL_DEPOT" list 2>&1)
assert_contains "list shows no skills" "No skills" "$output"

# Test 4: Add from GitHub URL (using a real skill from anthropics/skills)
echo "Test: add from GitHub URL"
"$SKILL_DEPOT" add https://github.com/anthropics/skills#skills/pdf
assert_file_exists "SKILL.md exists after add" ".claude/skills/pdf/SKILL.md"

# Test 5: List shows installed skill
echo "Test: list shows installed skill"
output=$("$SKILL_DEPOT" list 2>&1)
assert_contains "list shows pdf skill" "pdf" "$output"

# Test 6: Idempotent add
echo "Test: idempotent add"
output=$("$SKILL_DEPOT" add https://github.com/anthropics/skills#skills/pdf 2>&1)
assert_contains "idempotent message" "already installed" "$output"

# Test 7: Remove
echo "Test: remove skill"
"$SKILL_DEPOT" remove pdf
assert_dir_not_exists "skill dir removed" ".claude/skills/pdf"

# Test 8: Remove nonexistent skill fails
echo "Test: remove nonexistent skill"
if output=$("$SKILL_DEPOT" remove nonexistent 2>&1); then
  echo "  FAIL: should have exited non-zero"
  ((FAIL++))
else
  assert_contains "error message for missing skill" "not installed" "$output"
fi

# Test 9: Add from registry short name
echo "Test: add from registry short name"
"$SKILL_DEPOT" add pdf
assert_file_exists "SKILL.md from registry add" ".claude/skills/pdf/SKILL.md"

# Cleanup for next test
"$SKILL_DEPOT" remove pdf

# Test 10: Add with invalid GitHub URL (clone failure)
echo "Test: add with invalid URL"
if output=$("$SKILL_DEPOT" add https://github.com/nonexistent/repo-does-not-exist-xyz 2>&1); then
  echo "  FAIL: should have exited non-zero"
  FAIL=$((FAIL + 1))
else
  assert_contains "error message for bad URL" "failed to clone" "$output"
fi

# Test 11: Add with unknown registry name
echo "Test: add with unknown registry name"
if output=$("$SKILL_DEPOT" add nonexistent-skill-xyz 2>&1); then
  echo "  FAIL: should have exited non-zero"
  FAIL=$((FAIL + 1))
else
  assert_contains "error for unknown skill" "not found in registry" "$output"
fi

# Test 12: Add with invalid skill name (path traversal)
echo "Test: add with invalid skill name"
if output=$("$SKILL_DEPOT" add "../../etc" 2>&1); then
  echo "  FAIL: should have exited non-zero"
  FAIL=$((FAIL + 1))
else
  assert_contains "error for invalid name" "invalid skill name" "$output"
fi

# Test 13: Remove with invalid skill name (path traversal)
echo "Test: remove with invalid skill name"
if output=$("$SKILL_DEPOT" remove "../.git" 2>&1); then
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
