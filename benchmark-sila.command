#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
swiftc -O -module-cache-path build/ModuleCache Sources/Core.swift Benchmarks/SILA1500/main.swift -o build/benchmark-sila
build/benchmark-sila Examples/SILA-1500/SILA-1500.osched Examples/SILA-1500/performance.json
