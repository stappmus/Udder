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
mkdir -p -- "$smoke_root/proc" "$smoke_root/bin" "$smoke_root/runtime" "$smoke_root/state/omarchy"

cat >"$smoke_root/state/omarchy/udder.json" <<'JSON'
{
  "schemaVersion": 2,
  "pending": {},
  "remoteTracking": {
    "WyJ0ZXN0Ym94IiwiZGVmYXVsdCJd": true
  }
}
JSON

cat >"$smoke_root/bin/ssh" <<'SCRIPT'
#!/bin/bash
printf '%s\n' '{"result":{"snapshot":{"version":"0.8.2","protocol":20,"workspaces":[],"tabs":[],"panes":[],"agents":[]}}}'
SCRIPT
chmod +x "$smoke_root/bin/ssh"

focus_pane=""
if command -v herdr >/dev/null 2>&1; then
  focus_pane=$(herdr api snapshot 2>/dev/null | jq -r '.result.snapshot.focused_pane_id // ""' 2>/dev/null || true)
fi

set +e
output=$(UDDER_SMOKE_PANE_ID="$focus_pane" XDG_STATE_HOME="$smoke_root/state" \
  UDDER_PROC_ROOT="$smoke_root/proc" UDDER_RUNTIME_ROOT="$smoke_root/runtime" \
  UDDER_SSH_BIN="$smoke_root/bin/ssh" \
  timeout --kill-after=2s 8s quickshell --no-color -p "$smoke_root" 2>&1)
status=$?
set -e
printf '%s\n' "$output"
if ((status != 0)); then
  printf 'quickshell smoke test exited with status %s\n' "$status" >&2
  exit "$status"
fi
grep -q 'udder qml smoke passed' <<<"$output"
