#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

sound_path=$("$repo_root/udder-sound" --print-path)
[[ $sound_path == "$repo_root/assets/herdr-done.mp3" ]]
[[ -f $sound_path ]]
[[ $(sha256sum "$sound_path" | cut -d' ' -f1) == cb9c93492c808e33946edac2ab5915758267e65914bc4b794a5ca6dc6e655741 ]]

capture="$test_root/capture"
fake_player="$test_root/player"
cat >"$fake_player" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$UDDER_TEST_CAPTURE"
SCRIPT
chmod +x "$fake_player"

UDDER_TEST_CAPTURE="$capture" UDDER_SOUND_PLAYER="$fake_player" "$repo_root/udder-sound"
[[ $(<"$capture") == "$sound_path" ]]

rm -- "$capture"
UDDER_TEST_CAPTURE="$capture" UDDER_SOUND_PLAYER="$fake_player" HERDR_DISABLE_SOUND=1 \
  "$repo_root/udder-sound"
[[ ! -e $capture ]]

printf 'udder-sound tests passed\n'
