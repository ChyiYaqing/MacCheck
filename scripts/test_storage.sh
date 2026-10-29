#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -swift-version 6 -module-cache-path "$test_dir/module-cache" \
    -import-objc-header Sources/App/MacCheck-Bridging-Header.h \
    Sources/Core/StorageService/*.swift Sources/Core/ShellRunner.swift \
    Sources/Core/ReportEngine/ReportModel.swift Tests/StorageServiceTests.swift -o "$test_dir/storage-tests"
"$test_dir/storage-tests" "$@"
