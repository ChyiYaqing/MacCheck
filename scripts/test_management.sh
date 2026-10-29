#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -swift-version 6 -module-cache-path "$test_dir/module-cache" \
    Sources/Core/ManagementService/ManagementService.swift \
    Sources/Core/ShellRunner.swift Sources/Core/ReportEngine/ReportModel.swift \
    Tests/ManagementServiceTests.swift -o "$test_dir/management-tests"
"$test_dir/management-tests" "$@"
