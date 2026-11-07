#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
swiftc -O -module-cache-path build/ModuleCache Sources/Core.swift Benchmarks/main.swift -o build/benchmark
build/benchmark
