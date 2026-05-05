#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:-main}"

echo "🔄 Fetching from origin (fork)..."
git fetch origin

echo "⬇️  Pulling origin/$BRANCH into $BRANCH..."
git pull origin "$BRANCH"

echo "✅ Sync complete. Branch: $BRANCH"
