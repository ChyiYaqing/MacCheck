#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -swift-version 6 -module-cache-path "$test_dir/module-cache" \
    Sources/Core/PortService/PortService.swift Sources/Core/ShellRunner.swift \
    Sources/Core/ReportEngine/ReportModel.swift Tests/PortServiceTests.swift -o "$test_dir/port-tests"
"$test_dir/port-tests" "$@"
