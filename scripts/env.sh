# The Command Line Tools ship the macOS 27 SDK, whose @State is a macro, without the SwiftUIMacros plugin that expands it.
CLT=/Library/Developer/CommandLineTools
USING_CLT=0
if [[ "$(xcode-select -p)" == "$CLT"* ]]; then
    USING_CLT=1
    if [ -z "${SDKROOT:-}" ] && [ -d "$CLT/SDKs/MacOSX26.sdk" ]; then export SDKROOT="$CLT/SDKs/MacOSX26.sdk"; fi
fi
