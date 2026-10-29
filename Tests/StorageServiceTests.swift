import Foundation

func L(_ chinese: String, _ english: String) -> String { english }

@main
enum StorageServiceTests {
    static func main() {
        let details = StorageService.storageChipDetails(characteristics: [
            "vendor-name": "Toshiba   ", "nand-marketing-name": "tlc_3d_g5_2p_512 \0",
            "chip-id": "S5E",
        ])
        precondition(details["NAND manufacturer"] == "Toshiba")
        precondition(details["NAND model identifier"] == "tlc_3d_g5_2p_512")
        precondition(details["Storage controller chip"] == "S5E")
        for properties: [String: Any]? in [nil, [:], ["vendor-name": 123, "nand-marketing-name": "  "]] {
            let missing = StorageService.storageChipDetails(characteristics: properties)
            precondition(missing["NAND manufacturer"] == "Unavailable" && missing["NAND model identifier"] == "Unavailable")
            precondition(missing["Storage controller chip"] == nil)
        }
        precondition(StorageService.storageControllerCharacteristics(serial: "").isEmptyOrNil)
        precondition(StorageService.storageControllerCharacteristics(serial: "nonexistent-test-ssd").isEmptyOrNil)
        print("PASS: chip field parsing, missing/invalid fields, and controller matching")
        if CommandLine.arguments.contains("--live") {
            let results = StorageService.runAll()
            precondition(results.first?.rawDetails["NAND manufacturer"] == "Toshiba")
            precondition(results.first?.rawDetails["NAND model identifier"] == "tlc_3d_g5_2p_512")
            print("PASS: this Mac’s storage report includes NAND manufacturer and model")
        }
    }
}

private extension Optional where Wrapped == [String: Any] {
    var isEmptyOrNil: Bool { self == nil || self?.isEmpty == true }
}
