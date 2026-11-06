#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/ArankPlanner.app/Contents/MacOS
swiftc -target arm64-apple-macos14.0 -module-cache-path build/ModuleCache -O -parse-as-library Sources/Core.swift Sources/Controls.swift Sources/App.swift -o build/ArankPlanner.app/Contents/MacOS/ArankPlanner -framework SwiftUI -framework AppKit
cp Info.plist build/ArankPlanner.app/Contents/Info.plist
xattr -cr build/ArankPlanner.app
if ! codesign --force --deep --sign - build/ArankPlanner.app; then
  xattr -cr build/ArankPlanner.app
  codesign --force --deep --sign - build/ArankPlanner.app
fi
printf 'Готово: build/ArankPlanner.app\n'
