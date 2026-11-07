#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
sed '/^final class Lifecycle:/,$d' Sources/App.swift > build/Workspace-check.swift
swiftc -O -module-cache-path build/ModuleCache Sources/Core.swift build/Workspace-check.swift Tests/CalculationMode.swift -o build/calculation-mode-check -framework SwiftUI -framework AppKit
build/calculation-mode-check
