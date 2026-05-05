#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:-main}"

echo "🔄 Fetching from upstream (repo original del profesor)..."
git fetch upstream

echo "⬇️  Merging upstream/$BRANCH into $BRANCH..."
git merge upstream/"$BRANCH"

echo "⬆️  Pushing updated $BRANCH to origin (tu fork)..."
git push origin "$BRANCH"

echo "✅ Sync complete. Branch: $BRANCH"
