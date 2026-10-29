#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="$HOME/Applications/NoteToIssue.app"
"$ROOT_DIR/script/build_and_run.sh" --build-only
pkill -x NoteToIssue >/dev/null 2>&1 || true
mkdir -p "$HOME/Applications"
/usr/bin/ditto "$ROOT_DIR/dist/NoteToIssue.app" "$DESTINATION"
/usr/bin/open "$DESTINATION"
echo "Installée : $DESTINATION"
