#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
smoke_root=$(mktemp -d)
trap 'rm -rf -- "$smoke_root"' EXIT

cp -- "$repo_root/tests/qml-smoke.qml" "$smoke_root/shell.qml"
ln -s -- "$repo_root" "$smoke_root/plugin"
ln -s -- /usr/share/omarchy/shell/Commons "$smoke_root/Commons"
ln -s -- /usr/share/omarchy/shell/Ui "$smoke_root/Ui"
mkdir -p -- "$smoke_root/state"

focus_pane=""
if command -v herdr >/dev/null 2>&1; then
  focus_pane=$(herdr api snapshot 2>/dev/null | jq -r '.result.snapshot.focused_pane_id // ""' 2>/dev/null || true)
fi

set +e
output=$(UDDER_SMOKE_PANE_ID="$focus_pane" XDG_STATE_HOME="$smoke_root/state" \
  timeout --kill-after=2s 8s quickshell --no-color -p "$smoke_root" 2>&1)
status=$?
set -e
printf '%s\n' "$output"
if ((status != 0)); then
  printf 'quickshell smoke test exited with status %s\n' "$status" >&2
  exit "$status"
fi
grep -q 'udder qml smoke passed' <<<"$output"
