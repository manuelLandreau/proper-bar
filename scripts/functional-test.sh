#!/bin/bash
# Drives the real app in --demo mode through the Accessibility API: the terminal running this needs
# System Settings > Privacy & Security > Accessibility. Moves the mouse and briefly covers the main screen.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
swift build -c release --product ProperBar
PROPERBAR_BINARY="$PWD/.build/release/ProperBar" exec ./scripts/test.sh --filter ProperBarFunctionalTests "$@"
