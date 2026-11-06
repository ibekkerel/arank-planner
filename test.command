#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
swiftc -module-cache-path build/ModuleCache Sources/Core.swift Tests/main.swift -o build/tests
build/tests Examples/construction.osched
