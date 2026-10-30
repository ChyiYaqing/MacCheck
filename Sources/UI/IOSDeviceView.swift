import SwiftUI
import AppKit

/// 一台已连接 iPhone / iPad（或经由 iPhone 读取的 Apple Watch）的检测状态。
struct IOSDevice: Identifiable {
    enum Phase { case scanning, untrusted, ready }

    let summary: IOSDeviceSummary
    /// Apple Watch：读取它所经由的 iPhone；iPhone / iPad 为 nil。
    var parentUDID: String?
    var phase: Phase = .scanning
    var profile: DeviceProfile?
    var results: [CheckResult] = []
    var generatedAt = Date()

    var id: String { summary.udid }

    /// 侧边栏状态：取最严重的一项，规则与 Mac 分类一致。
    var status: CheckStatus? {
        let statuses = results.map(\.status)
        if statuses.contains(.redFlag) { return .redFlag }
        if statuses.contains(.warning) { return .warning }
        return statuses.isEmpty ? nil : .pass
    }

    var report: MacCheckReport {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        var rep = MacCheckReport(generatedAt: generatedAt, appVersion: version)
        rep.results = results
        return rep
    }
}

/// iPhone / iPad 检测状态。独立于 Mac 自检的 AppModel：结果只进各设备导出的报告，不计入 Mac 评分。
@MainActor
final class IOSDeviceModel: ObservableObject {
    @Published private(set) var isToolInstalled = true
    /// 按连接先后排序。
    @Published private(set) var devices: [IOSDevice] = []

    var iPhones: [IOSDevice] { devices.filter { $0.summary.kind == .iPhone } }
    var iPads: [IOSDevice] { devices.filter { $0.summary.kind == .iPad } }
    var watches: [IOSDevice] { devices.filter { $0.summary.kind == .watch } }

    func device(_ udid: String) -> IOSDevice? {
        devices.first { $0.id == udid }
    }

    /// App 运行期间每 2 秒轮询一次 USB 设备列表：新插入的设备自动检测，拔出的设备从列表移除。
    func monitor() async {
        while !Task.isCancelled {
            await refreshDeviceList()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func refreshDeviceList() async {
        let installed = IOSDeviceService.isToolInstalled
        if installed != isToolInstalled { isToolInstalled = installed }
        guard installed else { return }

        let known = Set(devices.map(\.id))
        let (udids, added) = await Task.detached { () -> ([String], [IOSDeviceSummary]) in
            let udids = IOSDeviceService.connectedUDIDs()
            return (udids, udids.filter { !known.contains($0) }.map { IOSDeviceService.summary(udid: $0) })
        }.value
        let remaining = devices.filter { udids.contains($0.parentUDID ?? $0.id) }   // 手表随其 iPhone 一起移除
        guard remaining.count != devices.count || !added.isEmpty else { return }
        devices = remaining + added.map { IOSDevice(summary: $0) }
        for summary in added {
            Task { await scan(summary.udid) }
        }
    }

    func scan(_ udid: String) async {
        if let iPhoneUDID = device(udid)?.parentUDID {
            await scanWatches(of: iPhoneUDID)
            return
        }
        update(udid) { $0.phase = .scanning }
        let outcome = await Task.detached(priority: .userInitiated) { IOSDeviceService.scan(udid: udid) }.value
        update(udid) { device in
            device.profile = outcome?.0
            device.results = outcome?.1 ?? []
            device.generatedAt = Date()
            device.phase = outcome == nil ? .untrusted : .ready
        }
        if outcome != nil, device(udid)?.summary.kind == .iPhone {
            await scanWatches(of: udid)
        }
    }

    /// 读取 iPhone 配对的手表，替换该 iPhone 名下原有的手表条目。
    private func scanWatches(of iPhoneUDID: String) async {
        for index in devices.indices where devices[index].parentUDID == iPhoneUDID {
            devices[index].phase = .scanning
        }
        let watches = await Task.detached(priority: .userInitiated) {
            WatchCompanionService.pairedWatches(iPhoneUDID: iPhoneUDID)
        }.value
        guard device(iPhoneUDID) != nil else { return }   // 读取期间 iPhone 被拔出
        devices.removeAll { $0.parentUDID == iPhoneUDID }
        devices += watches.map {
            IOSDevice(summary: $0.summary, parentUDID: iPhoneUDID, phase: .ready, profile: $0.profile, results: $0.results)
        }
    }

    /// 检测结果的文案是检测时生成的，切换语言后全部重测一遍。
    func rescanAll() {
        for device in devices where device.parentUDID == nil {   // 手表随 iPhone 重测
            Task { await scan(device.id) }
        }
    }

    /// 检测期间设备被拔出时直接丢弃结果。
    private func update(_ udid: String, _ change: (inout IOSDevice) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == udid }) else { return }
        change(&devices[index])
    }
}

/// 单台设备的检测详情页。
struct IOSDeviceView: View {
    @EnvironmentObject private var ios: IOSDeviceModel
    let udid: String

    var body: some View {
        let device = ios.device(udid)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                if let device {
                    CheckHeader(icon: device.summary.symbolName,
                                title: device.summary.name, subtitle: device.summary.subtitle)
                    content(device)
                } else {
                    InlineNotice(icon: "cable.connector", tint: .secondary,
                        text: L("设备已断开连接。重新连接后会出现在左侧 iPhone / iPad 分组。", "The device was disconnected. Reconnect it and it will appear under iPhone / iPad in the sidebar."))
                }
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(device?.summary.name ?? "iPhone / iPad")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await ios.scan(udid) }
                } label: {
                    Label(L("重新检测", "Check Again"), systemImage: "arrow.clockwise")
                }
                .disabled(device == nil || device?.phase == .scanning)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        if let device { ReportExporter.export(profile: device.profile, report: device.report, format: .png) }
                    } label: { Label(L("导出为长图 (PNG)", "Export as Long Image (PNG)"), systemImage: "photo") }
                    Button {
                        if let device { ReportExporter.export(profile: device.profile, report: device.report, format: .pdf) }
                    } label: { Label(L("导出为 PDF", "Export as PDF"), systemImage: "doc.richtext") }
                } label: {
                    Label(L("导出报告", "Export Report"), systemImage: "square.and.arrow.up")
                }
                .disabled(device?.phase != .ready)
            }
        }
    }

    @ViewBuilder
    private func content(_ device: IOSDevice) -> some View {
        switch device.phase {
        case .scanning:
            ProgressView(L("正在读取设备信息…", "Reading device info…"))
        case .untrusted:
            InlineNotice(icon: "hand.raised", tint: .orange,
                text: L("设备尚未信任这台 Mac。请解锁设备，在弹出的「要信任此电脑吗？」中点「信任」并输入锁屏密码，然后点「重新检测」。", "The device doesn't trust this Mac yet. Unlock it, tap Trust on the \"Trust This Computer?\" prompt and enter the passcode, then click Check Again."))
        case .ready:
            if let iPhone = device.parentUDID.flatMap(ios.device) {
                InlineNotice(icon: "iphone", tint: .secondary,
                    text: L("经由配对的 iPhone「\(iPhone.summary.name)」读取。Apple Watch 没有数据接口，部分项目只能在手表上人工确认。", "Read through the paired iPhone \"\(iPhone.summary.name)\". Apple Watch has no data port, so some items must be checked on the watch itself."))
            }
            if let p = device.profile { profileCard(p, symbol: device.summary.symbolName) }
            ForEach(device.results) { ResultCard(result: $0) }
        }
    }

    private func profileCard(_ p: DeviceProfile, symbol: String) -> some View {
        Card {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: symbol)
                    .foregroundStyle(.tint).font(.system(size: 13, weight: .semibold))
                SectionLabel(text: L("基础信息", "Basics"))
                Spacer()
            }
            KeyValueList {
                KVRow(icon: symbol, key: L("机型", "Model"), value: p.marketingName)
                KVRow(icon: "barcode", key: L("序列号", "Serial number"), value: p.serialNumber, mono: true, copyable: true)
                KVRow(icon: "tag", key: L("型号标识", "Model identifier"), value: p.modelIdentifier, mono: true)
                KVRow(icon: "number", key: L("型号号码", "Model number"), value: p.chip, mono: true)
                if !p.memory.isEmpty {   // 手表读不到存储
                    KVRow(icon: "internaldrive", key: L("存储容量", "Storage"), value: p.memory)
                }
                KVRow(icon: "apple.logo", key: L("系统版本", "OS version"), value: p.macOSVersion, last: true)
            }
            Button {
                if let url = URL(string: "https://checkcoverage.apple.com/") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(L("在 Apple 官网查询保修", "Check Warranty on Apple.com"), systemImage: "safari")
            }
            .buttonStyle(.bordered)
        }
    }
}

/// 未安装 libimobiledevice 时的引导页。
struct IOSSetupView: View {
    @EnvironmentObject private var ios: IOSDeviceModel

    private static let installCommand = "brew install libimobiledevice"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                CheckHeader(icon: "iphone", title: "iPhone / iPad",
                    subtitle: L("用数据线把 iPhone 或 iPad 连到这台 Mac，自动读取型号、序列号、销售渠道、电池、激活与监管状态。", "Connect an iPhone or iPad to this Mac with a cable to read its model, serial number, sales channel, battery, activation and supervision status."))
                if ios.isToolInstalled {
                    InlineNotice(icon: "checkmark.circle", tint: .green,
                        text: L("检测工具已安装。连接设备后会出现在左侧 iPhone / iPad 分组。", "The tools are installed. Connected devices appear under iPhone / iPad in the sidebar."))
                } else {
                    Card {
                        InlineNotice(icon: "shippingbox", tint: .orange,
                            text: L("需要先安装开源工具 libimobiledevice 才能读取 iPhone / iPad。在「终端」中运行下面的命令，安装完成后左侧会自动显示已连接的设备。", "The open-source libimobiledevice tools are needed to read an iPhone or iPad. Run the command below in Terminal; connected devices appear in the sidebar once it's installed."))
                        HStack {
                            Text(Self.installCommand).font(DS.Font.body.monospaced()).textSelection(.enabled)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(Self.installCommand, forType: .string)
                            } label: {
                                Label(L("复制命令", "Copy Command"), systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("iPhone / iPad")
    }
}
