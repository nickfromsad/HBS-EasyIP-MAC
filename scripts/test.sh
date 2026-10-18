#!/bin/bash
# Runs the unit tests. With only the Command Line Tools installed (no Xcode), SwiftPM
# cannot find the Swift Testing framework on its own, so point it there explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

CLT=/Library/Developer/CommandLineTools
if [[ "$(xcode-select -p)" == "$CLT" ]]; then
    FW="$CLT/Library/Developer/Frameworks"
    LIB="$CLT/Library/Developer/usr/lib"
    exec swift test -Xswiftc -F"$FW" -Xlinker -F"$FW" -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$LIB" "$@"
fi
exec swift test "$@"
