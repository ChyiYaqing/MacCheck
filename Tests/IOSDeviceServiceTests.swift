import Foundation

func L(_ chinese: String, _ english: String) -> String { english }

@main
enum IOSDeviceServiceTests {
    static func main() {
        precondition(IOSDeviceService.parseUDIDs("abc\n\n  def \nabc\n") == ["abc", "def"])
        print("PASS: UDID list trims blanks and duplicates")

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>ProductType</key><string>iPad5,2</string>
        <key>ProductVersion</key><string>15.8.8</string>
        <key>BuildVersion</key><string>19H422</string>
        <key>ModelNumber</key><string>MK8D2</string>
        <key>RegionInfo</key><string>LL/A</string>
        <key>SerialNumber</key><string>TESTSERIAL</string>
        <key>ActivationState</key><string>Activated</string>
        </dict></plist>
        """
        let info = IOSDeviceService.plist(xml)
        precondition(IOSDeviceService.plist("ERROR: Password protected").isEmpty)
        let profile = IOSDeviceService.profile(info: info, disk: ["TotalDiskCapacity": 128_000_000_000])
        precondition(profile.marketingName == "iPad mini 4")
        precondition(profile.macOSVersion == "iPadOS 15.8.8 (19H422)")
        precondition(profile.chip == "MK8D2LL/A" && profile.memory == "128 GB")
        precondition(IOSDeviceNaming.marketingName("iPhone99,9") == "iPhone99,9")
        print("PASS: profile built from ideviceinfo plist; unknown models fall back to ProductType")

        let phone = IOSDeviceService.summary(udid: "u1", info: ["DeviceClass": "iPhone", "DeviceName": "Test iPhone", "ProductType": "iPhone14,5", "ProductVersion": "18.1"])
        precondition(phone.kind == .iPhone && phone.name == "Test iPhone" && phone.subtitle == "iPhone 13 · iOS 18.1")
        let pad = IOSDeviceService.summary(udid: "u2", info: ["DeviceClass": "iPad", "ProductType": "iPad5,2", "ProductVersion": "15.8.8"])
        precondition(pad.kind == .iPad && pad.name == "iPad mini 4" && pad.subtitle == "iPad mini 4 · iPadOS 15.8.8")
        precondition(IOSDeviceService.summary(udid: "u3", info: [:]).name == "u3")
        print("PASS: device summary splits iPhone / iPad and falls back to model name, then UDID")

        let watch = WatchCompanionService.watch(udid: "w1", info: [
            "ProductType": "Watch6,15", "ProductVersion": "26.6", "BuildVersion": "23U67", "DeviceName": "Test Watch",
            "ModelNumber": "MNP83", "RegionInfo": "CH/A", "SerialNumber": "TESTSERIAL", "BatteryCurrentCapacity": 90, "BatteryIsCharging": false,
        ])
        precondition(watch.summary.kind == .watch && watch.summary.subtitle == "Apple Watch Series 8 · watchOS 26.6")
        precondition(watch.profile.macOSVersion == "watchOS 26.6 (23U67)" && watch.profile.memory.isEmpty)
        precondition(watch.results.map(\.id) == ["ios.identity", "ios.modelNumber", "ios.watch.battery", "ios.watch.activationLock"])
        precondition(watch.results[1].status == .pass && watch.results[2].summary.hasPrefix("Current charge 90%."))
        print("PASS: Apple Watch registry values become a watchOS profile with battery health and Activation Lock marked unsupported")

        precondition(IOSDeviceService.formatBytes(1_000_000_000_000) == "1 TB")
        precondition(IOSDeviceService.formatBytes(67_636_117_504) == "67.6 GB")
        print("PASS: capacities use decimal GB/TB")

        let retail = IOSDeviceService.modelNumberResult(info)
        precondition(retail.status == .pass && retail.summary.contains("US model"))
        let refurb = IOSDeviceService.modelNumberResult(["ModelNumber": "FK8D2", "RegionInfo": "CH/A"])
        precondition(refurb.status == .warning && refurb.summary.contains("Refurbished"))
        let replacement = IOSDeviceService.modelNumberResult(["ModelNumber": "NK8D2"])
        precondition(replacement.status == .warning && replacement.summary.contains("replacement"))
        print("PASS: model number prefix maps to sales channel (M retail, F refurbished, N replacement)")

        precondition(IOSDeviceService.supervisionResult([:]).status == .pass)
        let supervised = IOSDeviceService.supervisionResult(["DeviceIsChaperoned": true])
        precondition(supervised.status == .redFlag && supervised.isRedFlagHeadline != nil)
        print("PASS: supervised device is a red flag")

        let locked = IOSDeviceService.batteryResults([:])
        precondition(locked.count == 1 && locked[0].status == .unsupported)
        precondition(IOSDeviceService.batteryHealth(["BatteryData": ["MaximumCapacityPercent": 91], "DesignCapacity": 3000, "NominalChargeCapacity": 1500]) == 91)
        precondition(IOSDeviceService.batteryHealth(["DesignCapacity": 5124, "NominalChargeCapacity": 4100]) == 80)
        let nested = IOSDeviceService.batteryResults(["CycleCount": 1917, "BatteryData": ["DesignCapacity": 3208, "NominalChargeCapacity": 2243]])
        precondition(nested.map(\.id) == ["ios.battery.cycleCount", "ios.battery.health"] && nested[1].summary.contains("70%"))
        let worn = IOSDeviceService.batteryResults(["CycleCount": 950, "DesignCapacity": 5124, "AppleRawMaxCapacity": 2800])
        precondition(worn.map(\.status) == [.warning, .redFlag])
        print("PASS: battery health prefers MaximumCapacityPercent, falls back to capacity ratio; locked device is unsupported")

        if CommandLine.arguments.contains("--live") {
            let udids = IOSDeviceService.connectedUDIDs()
            guard !udids.isEmpty else {
                print("FAIL: no iPhone/iPad connected over USB"); exit(1)
            }
            for udid in udids {
                let summary = IOSDeviceService.summary(udid: udid)
                guard let (profile, results) = IOSDeviceService.scan(udid: udid) else {
                    print("LIVE: \(summary.kind) \(summary.subtitle) hasn't trusted this Mac"); continue
                }
                print("LIVE: \(summary.kind) · \(profile.marketingName) · \(profile.macOSVersion) · \(profile.memory)")
                for r in results { print("  \(r.status.rawValue)\t\(r.id)") }
                guard summary.kind == .iPhone else { continue }
                for watch in WatchCompanionService.pairedWatches(iPhoneUDID: udid) {
                    print("LIVE: watch · \(watch.profile.marketingName) · \(watch.profile.macOSVersion) · \(watch.profile.chip)")
                    for r in watch.results { print("  \(r.status.rawValue)\t\(r.id)\t\(r.id == "ios.watch.battery" ? r.summary.prefix(12) : "")") }
                }
            }
        }
    }
}
