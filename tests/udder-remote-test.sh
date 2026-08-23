#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

proc_root="$test_root/proc"
tmp_root="$test_root/tmp"
bin_root="$test_root/bin"
capture="$test_root/capture"
mkdir -p -- "$proc_root" "$tmp_root" "$bin_root"

make_process() {
  local pid="$1"
  shift
  mkdir -p -- "$proc_root/$pid"
  printf '%s\0' "$@" >"$proc_root/$pid/cmdline"
}

make_control() {
  local pid="$1"
  mkdir -p -- "$tmp_root/herdr-ssh-$pid-0"
  printf 'Host *\n' >"$tmp_root/herdr-ssh-$pid-0/config"
  : >"$tmp_root/herdr-ssh-$pid-0/ctl"
}

make_process 110 herdr
make_process 210 herdr --remote kontor
make_process 220 /usr/bin/herdr --session team --remote devbox
make_process 230 /usr/bin/herdr client
make_process 300 /usr/bin/herdr server
make_control 210
make_control 220

cat >"$bin_root/ssh" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$UDDER_TEST_CAPTURE"
printf '%s\n' '{"result":{"snapshot":{"version":"0.8.2","protocol":20,"workspaces":[],"tabs":[],"panes":[],"agents":[]}}}'
SCRIPT
chmod +x "$bin_root/ssh"

remote_env=(
  UDDER_PROC_ROOT="$proc_root"
  UDDER_TMP_ROOT="$tmp_root"
  UDDER_TEST_ALLOW_CONTROL_FILE=1
  UDDER_SSH_BIN="$bin_root/ssh"
  UDDER_TEST_CAPTURE="$capture"
)

discovered=$(env "${remote_env[@]}" "$repo_root/udder-remote" discover)
[[ $(jq length <<<"$discovered") -eq 2 ]]
[[ $(jq -r '.[0].target' <<<"$discovered") == kontor ]]
[[ $(jq -r '.[0].session' <<<"$discovered") == default ]]
[[ $(jq -r '.[1].target' <<<"$discovered") == devbox ]]
[[ $(jq -r '.[1].session' <<<"$discovered") == team ]]

snapshot=$(env "${remote_env[@]}" "$repo_root/udder-remote" snapshot 210)
[[ $(jq -r '.result.snapshot.protocol' <<<"$snapshot") == 20 ]]
mapfile -t default_args <"$capture"
[[ ${default_args[-2]} == kontor ]]
[[ ${default_args[-1]} == 'herdr api snapshot' ]]

env "${remote_env[@]}" "$repo_root/udder-remote" snapshot 220 >/dev/null
mapfile -t named_args <"$capture"
[[ ${named_args[-2]} == devbox ]]
[[ ${named_args[-1]} == 'herdr --session team api snapshot' ]]

if env "${remote_env[@]}" "$repo_root/udder-remote" snapshot 999 >/dev/null 2>&1; then
  printf 'missing remote process unexpectedly succeeded\n' >&2
  exit 1
fi

printf 'udder-remote tests passed\n'
