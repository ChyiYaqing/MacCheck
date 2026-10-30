#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -swift-version 6 -module-cache-path "$test_dir/module-cache" \
    Sources/Core/IOSDeviceService/*.swift Sources/Core/ShellRunner.swift \
    Sources/Core/ReportEngine/ReportModel.swift Tests/IOSDeviceServiceTests.swift -o "$test_dir/ios-device-tests"
# 与测试程序放在同一目录，Bundle.main.url(forAuxiliaryExecutable:) 才能找到（--live 读取 Apple Watch 用）
swiftc -swift-version 6 -module-cache-path "$test_dir/module-cache" \
    Helpers/WatchHelper/main.swift -o "$test_dir/MacCheckWatchHelper"
"$test_dir/ios-device-tests" "$@"
