#!/bin/bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$repo_root"

node tests/model.test.mjs
bash tests/udder-event-test.sh
bash tests/udder-integrate-test.sh
bash tests/udder-sound-test.sh
bash tests/udder-open-test.sh
bash tests/qml-smoke.sh

printf 'all tests passed\n'
