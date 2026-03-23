#!/bin/bash
# Start MetaClaw proxy for AutoResearchClaw integration.
#
# Usage:
#   ./scripts/metaclaw_start.sh              # skills_only mode (default)
#   ./scripts/metaclaw_start.sh madmax       # madmax mode (with RL training)
#   ./scripts/metaclaw_start.sh skills_only  # skills_only mode (explicit)

set -e

MODE="${1:-skills_only}"
PORT="${2:-30000}"

METACLAW_DIR="/home/jqliu/projects/MetaClaw"

if ! command -v poetry >/dev/null 2>&1; then
    echo "ERROR: Poetry is required but not installed"
    exit 1
fi

if ! (cd "$METACLAW_DIR" && poetry env info --path >/dev/null 2>&1); then
    echo "ERROR: MetaClaw Poetry environment not found for $METACLAW_DIR"
    echo "Run: cd $METACLAW_DIR && poetry install"
    exit 1
fi

echo "Starting MetaClaw in ${MODE} mode on port ${PORT}..."

cd "$METACLAW_DIR"
exec poetry run metaclaw start --mode "$MODE" --port "$PORT"
