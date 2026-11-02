#!/usr/bin/env bash
# Install the pre-commit hook that encrypts app-src/ and src/ on every commit.
set -euo pipefail
cd "$(dirname "$0")/.."
install -m 755 scripts/pre-commit .git/hooks/pre-commit
echo "Installed .git/hooks/pre-commit"
