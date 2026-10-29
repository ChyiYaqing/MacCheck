import Foundation

func L(_ chinese: String, _ english: String) -> String { english }

@main
enum PortServiceTests {
    static func main() {
        for (usb, tb, displays) in [([], [], ["Test display"]), (["USB Hub"], [], ["Test display"]),
                                    ([], ["Thunderbolt dock"], []), ([], [], [])] as [([String], [String], [String])] {
            let result = PortService.portResult(usb: usb, thunderbolt: tb, displays: displays)
            precondition(result.rawDetails["Connected external displays"] == (displays.isEmpty ? "None" : "Test display"))
            precondition(result.summary.contains("No USB") == (usb.isEmpty && tb.isEmpty && displays.isEmpty))
        }
        print("PASS: 4 port report cases (display only, USB hub plus display, Thunderbolt, no devices)")
        let deviceList = PortService.portResult(usb: ["USB Hub", "USB Storage"], thunderbolt: [], displays: [])
        precondition(deviceList.rawDetails["Connected USB devices"] == "USB Hub\nUSB Storage")
        print("PASS: USB devices are listed on separate lines")
        if CommandLine.arguments.contains("--live") {
            let result = PortService.runAll().first!
            guard result.rawDetails["Connected external displays"]?.contains("DELL P2723QE") == true,
                  !result.summary.contains("No USB or Thunderbolt devices connected") else {
                print("FAIL: connected DELL display is missing from the port report")
                exit(1)
            }
            print("PASS: DELL external display appears in the port report and summary")
        }
        if CommandLine.arguments.contains("--live-usb") {
            let result = PortService.runAll().first!
            let usb = result.rawDetails["Connected USB devices"] ?? ""
            guard usb.contains("USB Storage"), usb.contains("Hub") else {
                print("FAIL: connected USB dock and USB Storage are missing from the port report")
                exit(1)
            }
            print("PASS: connected USB dock and USB Storage appear in the port report")
        }
    }
}
