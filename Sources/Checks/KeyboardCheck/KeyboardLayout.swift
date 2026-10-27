import Foundation

/// 单个物理按键：macOS 虚拟 keyCode + 显示文案 + 相对宽度（1.0 = 一个标准键位）。
struct KeyDef: Identifiable, Hashable {
    let id: UInt16   // 用 keyCode 本身当 id，同一个键不会重复出现在布局里
    let keyCode: UInt16
    let label: String
    let widthUnits: CGFloat
    /// 同一个物理键可能发出的其他事件码：顶排默认是亮度/音量等媒体键（不按 fn 时），
    /// 收到这些码也算该键已测。媒体键码 = `KeyboardLayout.mediaBase + NX_KEYTYPE_*`。
    let altCodes: [UInt16]

    init(_ keyCode: UInt16, _ label: String, width: CGFloat = 1.0, alt: [UInt16] = []) {
        self.id = keyCode
        self.keyCode = keyCode
        self.label = label
        self.widthUnits = width
        self.altCodes = alt
    }

    var allCodes: [UInt16] { [keyCode] + altCodes }
}

/// 标准 macOS 美式 ANSI 键盘布局（无 Touch Bar）。虚拟 keyCode 定义参考 Carbon HIToolbox `Events.h`。
/// 说明：为简化渲染模型，方向键簇按四个等大按键横排展示，与实体键盘上下堆叠的 ↑/↓ 略有出入，
/// 不影响功能测试（每个方向键仍独立可测）。
enum KeyboardLayout {
    /// 媒体键（NSEvent.systemDefined, subtype 8）映射到的合成键码起点，避开真实虚拟键码范围。
    static let mediaBase: UInt16 = 0x1000
    private static func media(_ nxKeyType: UInt16) -> UInt16 { mediaBase + nxKeyType }

    // NX_KEYTYPE_*（IOKit/hidsystem/ev_keymap.h）
    private static let soundUp = media(0), soundDown = media(1), brightnessUp = media(2), brightnessDown = media(3)
    private static let mute = media(7), play = media(16), next = media(17), previous = media(18)
    private static let fast = media(19), rewind = media(20), illumUp = media(21), illumDown = media(22)

    static let rows: [[KeyDef]] = [
        // 功能键行：Apple 键盘顶排默认是媒体功能，按 fn 才是 F1–F12，两种都算已测（issue #5）。
        // F3–F6 在不同年代机型上是调度中心/启动台/聚焦/听写/勿扰，部分被系统直接拦截，可点击键位手动确认。
        [
            KeyDef(53, "esc"),
            KeyDef(122, "F1", alt: [brightnessDown]), KeyDef(120, "F2", alt: [brightnessUp]),
            KeyDef(99, "F3", alt: [160]), KeyDef(118, "F4", alt: [131, 177]),
            KeyDef(96, "F5", alt: [176, illumDown]), KeyDef(97, "F6", alt: [178, illumUp]),
            KeyDef(98, "F7", alt: [rewind, previous]), KeyDef(100, "F8", alt: [play]),
            KeyDef(101, "F9", alt: [fast, next]), KeyDef(109, "F10", alt: [mute]),
            KeyDef(103, "F11", alt: [soundDown]), KeyDef(111, "F12", alt: [soundUp]),
        ],
        // 数字行
        [
            KeyDef(50, "`"), KeyDef(18, "1"), KeyDef(19, "2"), KeyDef(20, "3"), KeyDef(21, "4"),
            KeyDef(23, "5"), KeyDef(22, "6"), KeyDef(26, "7"), KeyDef(28, "8"), KeyDef(25, "9"),
            KeyDef(29, "0"), KeyDef(27, "-"), KeyDef(24, "="), KeyDef(51, "delete", width: 1.8),
        ],
        // QWERTY 行
        [
            KeyDef(48, "tab", width: 1.4),
            KeyDef(12, "Q"), KeyDef(13, "W"), KeyDef(14, "E"), KeyDef(15, "R"), KeyDef(17, "T"),
            KeyDef(16, "Y"), KeyDef(32, "U"), KeyDef(34, "I"), KeyDef(31, "O"), KeyDef(35, "P"),
            KeyDef(33, "["), KeyDef(30, "]"), KeyDef(42, "\\", width: 1.2),
        ],
        // 主行（home row）
        [
            KeyDef(57, "caps", width: 1.7),
            KeyDef(0, "A"), KeyDef(1, "S"), KeyDef(2, "D"), KeyDef(3, "F"), KeyDef(5, "G"),
            KeyDef(4, "H"), KeyDef(38, "J"), KeyDef(40, "K"), KeyDef(37, "L"), KeyDef(41, ";"),
            KeyDef(39, "'"), KeyDef(36, "return", width: 2.0),
        ],
        // 下行
        [
            KeyDef(56, "shift", width: 2.2),
            KeyDef(6, "Z"), KeyDef(7, "X"), KeyDef(8, "C"), KeyDef(9, "V"), KeyDef(11, "B"),
            KeyDef(45, "N"), KeyDef(46, "M"), KeyDef(43, ","), KeyDef(47, "."), KeyDef(44, "/"),
            KeyDef(60, "shift", width: 2.2),
        ],
        // 底行
        [
            KeyDef(63, "fn", width: 1.0),
            KeyDef(59, "control", width: 1.2),
            KeyDef(58, "option", width: 1.2),
            KeyDef(55, "⌘", width: 1.4),
            KeyDef(49, "space", width: 5.0),
            KeyDef(54, "⌘", width: 1.2),
            KeyDef(61, "option", width: 1.2),
            KeyDef(123, "←"), KeyDef(126, "↑"), KeyDef(125, "↓"), KeyDef(124, "→"),
        ],
    ]

    static var allKeys: [KeyDef] { rows.flatMap { $0 } }
    static var totalKeyCount: Int { allKeys.count }

    /// 任意事件码 → 布局里的主 keyCode（媒体键/特殊键归并到对应 F 键）。
    static let canonicalCode: [UInt16: UInt16] = {
        var map: [UInt16: UInt16] = [:]
        for key in allKeys { for code in key.allCodes { map[code] = key.keyCode } }
        return map
    }()
}
