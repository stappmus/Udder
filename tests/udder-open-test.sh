#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

proc_root="$test_root/proc"
bin_root="$test_root/bin"
capture="$test_root/capture"
mkdir -p -- "$proc_root" "$bin_root"

make_process() {
  local pid="$1" ppid="$2"
  shift 2
  mkdir -p -- "$proc_root/$pid"
  printf 'Name:\ttest\nPPid:\t%s\n' "$ppid" >"$proc_root/$pid/status"
  printf '%s\0' "$@" >"$proc_root/$pid/cmdline"
}

make_process 100 1 alacritty
make_process 110 100 herdr
make_process 200 1 alacritty
make_process 210 200 herdr --remote kontor
make_process 211 210 /usr/bin/herdr client
make_process 300 1 /usr/bin/herdr server

cat >"$bin_root/pgrep" <<'SCRIPT'
#!/bin/bash
printf '%s\n' ${UDDER_TEST_PIDS:-110 210 211 300}
SCRIPT

cat >"$bin_root/hyprctl" <<'SCRIPT'
#!/bin/bash
if [[ ${1:-} == clients && ${2:-} == -j ]]; then
  printf '%s\n' '[
    {"address":"0x2222","workspace":{"id":3,"name":"3"},"pid":200,"mapped":true,"focusHistoryID":0},
    {"address":"0x1111","workspace":{"id":2,"name":"2"},"pid":100,"mapped":true,"focusHistoryID":4}
  ]'
  exit 0
fi
printf 'hyprctl' >>"$UDDER_TEST_CAPTURE"
printf '\t%s' "$@" >>"$UDDER_TEST_CAPTURE"
printf '\n' >>"$UDDER_TEST_CAPTURE"
SCRIPT

cat >"$bin_root/omarchy" <<'SCRIPT'
#!/bin/bash
printf 'omarchy' >>"$UDDER_TEST_CAPTURE"
printf '\t%s' "$@" >>"$UDDER_TEST_CAPTURE"
printf '\n' >>"$UDDER_TEST_CAPTURE"
SCRIPT

chmod +x "$bin_root/pgrep" "$bin_root/hyprctl" "$bin_root/omarchy"

run_open() {
  UDDER_PROC_ROOT="$proc_root" UDDER_PGREP_BIN="$bin_root/pgrep" \
    UDDER_HYPRCTL_BIN="$bin_root/hyprctl" UDDER_OMARCHY_BIN="$bin_root/omarchy" \
    UDDER_TEST_CAPTURE="$capture" "$repo_root/udder-open" "$@"
}

run_open
mapfile -t calls <"$capture"
[[ ${calls[0]} == $'hyprctl\tdispatch\thl.dsp.focus({ window = "address:0x1111" })' ]]
[[ ${#calls[@]} -eq 1 ]]

: >"$capture"
UDDER_TEST_PIDS='210 211 300' run_open
[[ $(<"$capture") == $'omarchy\tlaunch\tterminal\therdr' ]]

actual=$("$repo_root/udder-open" --dry-run)
[[ $actual == focus$'\t'* ]]

printf 'udder-open tests passed\n'
