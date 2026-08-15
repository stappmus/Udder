#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

registry="$test_root/registry.json"
calls="$test_root/calls"
fake_herdr="$test_root/herdr"

export UDDER_TEST_REGISTRY="$registry"
export UDDER_TEST_CALLS="$calls"

cat >"$fake_herdr" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

case "${1:-} ${2:-}" in
"plugin list")
  if [[ -f $UDDER_TEST_REGISTRY ]]; then
    plugin=$(<"$UDDER_TEST_REGISTRY")
    jq -cn --argjson plugin "$plugin" '{id:"test",result:{type:"plugin_list",plugins:[$plugin]}}'
  else
    jq -cn '{id:"test",result:{type:"plugin_list",plugins:[]}}'
  fi
  ;;
"plugin link")
  root=${3:?missing plugin root}
  jq -cn --arg root "$root" \
    '{id:"stappmus.udder",plugin_root:$root,enabled:true,warnings:[]}' >"$UDDER_TEST_REGISTRY"
  printf 'link\n' >>"$UDDER_TEST_CALLS"
  ;;
"plugin unlink")
  rm -f -- "$UDDER_TEST_REGISTRY"
  printf 'unlink\n' >>"$UDDER_TEST_CALLS"
  ;;
*)
  printf 'unexpected fake herdr call: %q ' "$@" >&2
  printf '\n' >&2
  exit 2
  ;;
esac
SCRIPT
chmod +x "$fake_herdr"

run_integrate() {
  HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" HERDR_BIN_PATH="$fake_herdr" \
    "$repo_root/udder-integrate" "$@"
}

first=$(run_integrate)
[[ $(jq -r .state <<<"$first") == ready ]]
[[ $(jq -r .plugin_root <"$registry") == "$repo_root" ]]
[[ $(<"$calls") == link ]]

second=$(run_integrate)
[[ $(jq -r .state <<<"$second") == ready ]]
[[ $(wc -l <"$calls") -eq 1 ]]

jq '.enabled = false' "$registry" >"$registry.next"
mv -- "$registry.next" "$registry"
disabled=$(run_integrate)
[[ $(jq -r .state <<<"$disabled") == disabled ]]
[[ $(wc -l <"$calls") -eq 1 ]]

jq '.plugin_root = "/tmp/a-different-udder"' "$registry" >"$registry.next"
mv -- "$registry.next" "$registry"
set +e
conflict=$(run_integrate)
conflict_status=$?
set -e
[[ $conflict_status -ne 0 ]]
[[ $(jq -r .state <<<"$conflict") == conflict ]]

jq --arg root "$repo_root" '.plugin_root = $root | .enabled = true' "$registry" >"$registry.next"
mv -- "$registry.next" "$registry"
unlinked=$(run_integrate --unlink)
[[ $(jq -r .state <<<"$unlinked") == ready ]]
[[ ! -e $registry ]]
[[ $(tail -n 1 "$calls") == unlink ]]

printf 'udder-integrate tests passed\n'
