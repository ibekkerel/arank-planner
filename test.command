#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
swiftc -module-cache-path build/ModuleCache Sources/Core.swift Tests/main.swift -o build/tests
build/tests "$scratch/construction.osched"
swiftc -module-cache-path build/ModuleCache Sources/Core.swift Sources/WorkspaceFilter.swift Tests/WorkspaceFilterCheck.swift -o build/workspace-filter-tests
build/workspace-filter-tests
