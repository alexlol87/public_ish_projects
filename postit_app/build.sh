#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
rm -rf PostIt.app
mkdir -p PostIt.app/Contents/MacOS PostIt.app/Contents/Resources
cp "$(swift build -c release --show-bin-path)/PostIt" PostIt.app/Contents/MacOS/
cp Info.plist PostIt.app/Contents/
cp Resources/* PostIt.app/Contents/Resources/
codesign --force --deep --sign - PostIt.app
echo "Built PostIt.app"
