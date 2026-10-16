#!/usr/bin/env bash
# Predict the bump semver.yml (devops/common/ci-templates) will compute.
# Mirrors detect_bump: scans every line of every commit message since the last
# stable tag, plus an optional candidate message file, and takes the highest.
#
# Usage: predict_bump.sh [candidate-message-file]
# Prints: <bump> <last-stable-tag-or-"none">
set -eu

prefix="${GIT_SEMVER_TAG_PREFIX:-v}"
last="$(git tag --list "${prefix}[0-9]*" --sort=-v:refname | grep -vE -- '-' | head -1 || true)"
range="${last:+${last}..}HEAD"
log="$(git log "$range" --pretty=%B 2>/dev/null || true)"
if [ -n "${1:-}" ]; then
  log="$(printf '%s\n%s\n' "$log" "$(cat "$1")")"
fi

if printf '%s\n' "$log" | grep -iqE '(^BREAKING CHANGE:|^BREAKING-CHANGE:|^[a-z]+(\([^)]+\))?!:)'; then
  bump=major
elif printf '%s\n' "$log" | grep -iqE '^feat(\([^)]+\))?:'; then
  bump=minor
elif printf '%s\n' "$log" | grep -iqE '^(fix|perf|refactor|revert|build|ci|chore|docs|style|test)(\([^)]+\))?:'; then
  bump=patch
else
  bump="${GIT_SEMVER_DEFAULT_BUMP:-patch} (default)"
fi
echo "$bump ${last:-none}"
