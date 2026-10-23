#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

# swift-testing's macro plugin lives outside the default search path under the Command Line Tools.
if [ "$USING_CLT" = 1 ]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" "$@"
fi
exec swift test "$@"
