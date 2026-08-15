#!/bin/bash

set -euo pipefail

test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

api_socket="$test_root/herdr.sock"
client_socket="$test_root/herdr-client.sock"
proc_table="$test_root/unix"
capture="$test_root/capture"
fake_shell="$test_root/omarchy-shell"

cat >"$fake_shell" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$UDDER_TEST_CAPTURE"
SCRIPT
chmod +x "$fake_shell"

write_table() {
  local state="$1"
  local path="${2:-}"
  printf 'Num RefCount Protocol Flags Type St Inode Path\n' >"$proc_table"
  printf '00000000: 00000003 00000000 00000000 0001 %s 12345 %s\n' "$state" "$path" >>"$proc_table"
}

write_table 03 "$client_socket"
attached=$(HERDR_SOCKET_PATH="$api_socket" UDDER_DEFAULT_SOCKET_PATH="$api_socket" UDDER_PROC_NET_UNIX="$proc_table" \
  "$PWD/udder-event" --client-attached)
[[ $attached == true ]]

UDDER_TEST_CAPTURE="$capture" UDDER_DEFAULT_SOCKET_PATH="$api_socket" \
  UDDER_PROC_NET_UNIX="$proc_table" UDDER_OMARCHY_SHELL="$fake_shell" \
  HERDR_SOCKET_PATH="$api_socket" HERDR_PLUGIN_EVENT_JSON='{"event":"pane_agent_status_changed"}' \
  "$PWD/udder-event"
[[ ! -e $capture ]]

write_table 01 "$client_socket"
detached=$(HERDR_SOCKET_PATH="$api_socket" UDDER_DEFAULT_SOCKET_PATH="$api_socket" UDDER_PROC_NET_UNIX="$proc_table" \
  "$PWD/udder-event" --client-attached)
[[ $detached == false ]]

UDDER_TEST_CAPTURE="$capture" UDDER_DEFAULT_SOCKET_PATH="$api_socket" \
  UDDER_PROC_NET_UNIX="$proc_table" UDDER_OMARCHY_SHELL="$fake_shell" \
  HERDR_SOCKET_PATH="$api_socket" HERDR_PLUGIN_EVENT_JSON='{"event":"pane_agent_status_changed"}' \
  HERDR_PLUGIN_CONTEXT_JSON='{"workspace_label":"Udder"}' "$PWD/udder-event"

mapfile -t args <"$capture"
[[ ${args[0]} == stappmus.udder ]]
[[ ${args[1]} == event ]]
[[ ${args[2]} == '{"event":"pane_agent_status_changed"}' ]]
[[ ${args[3]} == '{"workspace_label":"Udder"}' ]]

printf 'udder-event tests passed\n'
