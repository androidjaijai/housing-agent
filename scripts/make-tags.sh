#!/usr/bin/env bash
# Turn the release branches (claude/release/vX.Y.Z) into real git tags and push them.
# Run this on your own machine: the cloud session that built the app cannot push tags.
set -euo pipefail
cd "$(dirname "$0")/.."
git fetch origin 'refs/heads/claude/release/*:refs/remotes/origin/claude/release/*'
for ref in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin/claude/release/); do
  version="${ref##*/}"
  if git rev-parse -q --verify "refs/tags/$version" >/dev/null; then
    echo "tag $version exists, skipping"
  else
    git tag -a "$version" "$ref" -m "$version (from $ref)"
    echo "created tag $version -> $(git rev-parse --short "$ref")"
  fi
done
git push origin --tags
