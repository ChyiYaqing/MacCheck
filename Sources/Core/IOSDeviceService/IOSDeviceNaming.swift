import Foundation

/// iPhone / iPad / Apple Watch 型号标识（ProductType，如 "iPhone15,2"）→ 营销名。
/// iOS 设备没有类似 Mac `product-name` 的节点，只能维护对照表；表里没有的新机型直接显示原始标识。
enum IOSDeviceNaming {

    static func marketingName(_ productType: String) -> String {
        table[productType] ?? productType
    }

    private static let table: [String: String] = [
        // iPhone
        "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8",
        "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
        "iPhone11,2": "iPhone XS",
        "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",

        // iPad
        "iPad7,5": "iPad (6th generation)", "iPad7,6": "iPad (6th generation)",
        "iPad7,11": "iPad (7th generation)", "iPad7,12": "iPad (7th generation)",
        "iPad11,6": "iPad (8th generation)", "iPad11,7": "iPad (8th generation)",
        "iPad12,1": "iPad (9th generation)", "iPad12,2": "iPad (9th generation)",
        "iPad13,18": "iPad (10th generation)", "iPad13,19": "iPad (10th generation)",
        "iPad15,7": "iPad (A16)", "iPad15,8": "iPad (A16)",

        // iPad mini
        "iPad5,1": "iPad mini 4", "iPad5,2": "iPad mini 4",
        "iPad11,1": "iPad mini (5th generation)", "iPad11,2": "iPad mini (5th generation)",
        "iPad14,1": "iPad mini (6th generation)", "iPad14,2": "iPad mini (6th generation)",
        "iPad16,1": "iPad mini (A17 Pro)", "iPad16,2": "iPad mini (A17 Pro)",

        // iPad Air
        "iPad5,3": "iPad Air 2", "iPad5,4": "iPad Air 2",
        "iPad11,3": "iPad Air (3rd generation)", "iPad11,4": "iPad Air (3rd generation)",
        "iPad13,1": "iPad Air (4th generation)", "iPad13,2": "iPad Air (4th generation)",
        "iPad13,16": "iPad Air (5th generation)", "iPad13,17": "iPad Air (5th generation)",
        "iPad14,8": "iPad Air 11-inch (M2)", "iPad14,9": "iPad Air 11-inch (M2)",
        "iPad14,10": "iPad Air 13-inch (M2)", "iPad14,11": "iPad Air 13-inch (M2)",
        "iPad15,3": "iPad Air 11-inch (M3)", "iPad15,4": "iPad Air 11-inch (M3)",
        "iPad15,5": "iPad Air 13-inch (M3)", "iPad15,6": "iPad Air 13-inch (M3)",

        // iPad Pro
        "iPad8,1": "iPad Pro 11-inch", "iPad8,2": "iPad Pro 11-inch",
        "iPad8,3": "iPad Pro 11-inch", "iPad8,4": "iPad Pro 11-inch",
        "iPad8,5": "iPad Pro 12.9-inch (3rd generation)", "iPad8,6": "iPad Pro 12.9-inch (3rd generation)",
        "iPad8,7": "iPad Pro 12.9-inch (3rd generation)", "iPad8,8": "iPad Pro 12.9-inch (3rd generation)",
        "iPad8,9": "iPad Pro 11-inch (2nd generation)", "iPad8,10": "iPad Pro 11-inch (2nd generation)",
        "iPad8,11": "iPad Pro 12.9-inch (4th generation)", "iPad8,12": "iPad Pro 12.9-inch (4th generation)",
        "iPad13,4": "iPad Pro 11-inch (3rd generation)", "iPad13,5": "iPad Pro 11-inch (3rd generation)",
        "iPad13,6": "iPad Pro 11-inch (3rd generation)", "iPad13,7": "iPad Pro 11-inch (3rd generation)",
        "iPad13,8": "iPad Pro 12.9-inch (5th generation)", "iPad13,9": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,10": "iPad Pro 12.9-inch (5th generation)", "iPad13,11": "iPad Pro 12.9-inch (5th generation)",
        "iPad14,3": "iPad Pro 11-inch (4th generation)", "iPad14,4": "iPad Pro 11-inch (4th generation)",
        "iPad14,5": "iPad Pro 12.9-inch (6th generation)", "iPad14,6": "iPad Pro 12.9-inch (6th generation)",
        "iPad16,3": "iPad Pro 11-inch (M4)", "iPad16,4": "iPad Pro 11-inch (M4)",
        "iPad16,5": "iPad Pro 13-inch (M4)", "iPad16,6": "iPad Pro 13-inch (M4)",

        // Apple Watch
        "Watch3,1": "Apple Watch Series 3", "Watch3,2": "Apple Watch Series 3",
        "Watch3,3": "Apple Watch Series 3", "Watch3,4": "Apple Watch Series 3",
        "Watch4,1": "Apple Watch Series 4", "Watch4,2": "Apple Watch Series 4",
        "Watch4,3": "Apple Watch Series 4", "Watch4,4": "Apple Watch Series 4",
        "Watch5,1": "Apple Watch Series 5", "Watch5,2": "Apple Watch Series 5",
        "Watch5,3": "Apple Watch Series 5", "Watch5,4": "Apple Watch Series 5",
        "Watch5,9": "Apple Watch SE", "Watch5,10": "Apple Watch SE",
        "Watch5,11": "Apple Watch SE", "Watch5,12": "Apple Watch SE",
        "Watch6,1": "Apple Watch Series 6", "Watch6,2": "Apple Watch Series 6",
        "Watch6,3": "Apple Watch Series 6", "Watch6,4": "Apple Watch Series 6",
        "Watch6,6": "Apple Watch Series 7", "Watch6,7": "Apple Watch Series 7",
        "Watch6,8": "Apple Watch Series 7", "Watch6,9": "Apple Watch Series 7",
        "Watch6,10": "Apple Watch SE (2nd generation)", "Watch6,11": "Apple Watch SE (2nd generation)",
        "Watch6,12": "Apple Watch SE (2nd generation)", "Watch6,13": "Apple Watch SE (2nd generation)",
        "Watch6,14": "Apple Watch Series 8", "Watch6,15": "Apple Watch Series 8",
        "Watch6,16": "Apple Watch Series 8", "Watch6,17": "Apple Watch Series 8",
        "Watch6,18": "Apple Watch Ultra",
        "Watch7,1": "Apple Watch Series 9", "Watch7,2": "Apple Watch Series 9",
        "Watch7,3": "Apple Watch Series 9", "Watch7,4": "Apple Watch Series 9",
        "Watch7,5": "Apple Watch Ultra 2",
        "Watch7,8": "Apple Watch Series 10", "Watch7,9": "Apple Watch Series 10",
        "Watch7,10": "Apple Watch Series 10", "Watch7,11": "Apple Watch Series 10",
    ]
}
