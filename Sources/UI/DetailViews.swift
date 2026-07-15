import SwiftUI
import AppKit

/// 详情面板路由：概览 / 硬件规格 / 各检测分类 / 交互测试。
struct DetailRouter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.selection ?? .overview {
        case .overview:
            OverviewView()
        case .specs:
            SpecsView()
        case .keyboard:
            FullscreenLaunchPane(item: .keyboard, test: .keyboard,
                icon: "keyboard.fill", title: "键盘测试",
                subtitle: "全屏逐键点亮，按下的键即刻高亮，自动识别失灵与卡键。")
        case .screen:
            FullscreenLaunchPane(item: .screen, test: .screen,
                icon: "display", title: "屏幕测试",
                subtitle: "纯色、灰阶、棋盘格全套画面轮播，用于查找坏点、亮点、色带与漏光。")
        case .audio:
            AudioCheckView { model.recordTest($0) }
        case .microphone:
            MicrophoneCheckView { model.recordTest($0) }
        case .camera:
            CameraCheckView { model.recordTest($0) }
        case .touchID:
            TouchIDCheckView { model.recordTest($0) }
        case .trackpad:
            TrackpadCheckView { model.recordTest($0) }
        case .performance:
            PerformanceCheckView { model.recordTest($0) }
        case .diskSpeed:
            DiskSpeedCheckView { model.recordTest($0) }
        case .portsLive:
            PortLiveCheckView { model.recordTest($0) }
        case .aiModels:
            AIModelsView()
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        default:
            CategoryDetailView(item: model.selection ?? .overview)
        }
    }
}

// MARK: - 硬件规格（基础信息 · 系统 · 购买与保修）

struct SpecsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                if let p = model.profile {
                    basicInfoCard(p)
                    systemCard(p)
                    warrantyCard(p)
                } else {
                    ProgressView("正在读取硬件规格…")
                }
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("硬件规格")
    }

    // 基础信息
    private func basicInfoCard(_ p: DeviceProfile) -> some View {
        Card {
            cardHeader(icon: "laptopcomputer", title: "基础信息")
            KeyValueList {
                KVRow(icon: "macbook", key: "机型", value: p.marketingName)
                KVRow(icon: "barcode", key: "序列号", value: p.serialNumber, mono: true, copyable: true)
                KVRow(icon: "tag", key: "型号标识", value: p.modelIdentifier, mono: true)
                KVRow(icon: "cpu", key: "芯片", value: p.chip)
                KVRow(icon: "memorychip", key: "内存", value: p.memory)
                KVRow(icon: "square.stack.3d.up", key: "架构", value: p.architecture, last: true)
            }
        }
    }

    // 系统
    private func systemCard(_ p: DeviceProfile) -> some View {
        Card {
            cardHeader(icon: "gearshape", title: "系统")
            KeyValueList {
                KVRow(icon: "apple.logo", key: "操作系统", value: p.macOSVersion, last: true)
            }
        }
    }

    // 购买与保修
    private func warrantyCard(_ p: DeviceProfile) -> some View {
        let lock = model.result(id: "management.activationLock")
        return Card {
            cardHeader(icon: "checkmark.seal", title: "购买与保修")
            KeyValueList {
                KVRow(icon: "calendar", key: "机型年份", value: p.modelYear.isEmpty ? "未知" : p.modelYear)
                KVRow(icon: "clock.arrow.circlepath", key: "预计机龄", value: ageText(p.modelYear))
                KVRow(icon: "hammer", key: "生产日期", value: p.productionDate)
                KVRow(icon: "lock.shield",
                      key: "激活锁",
                      value: lock?.summary ?? "见「安全与锁定」",
                      valueTint: lock?.status.tint,
                      last: true)
            }

            InlineNotice(icon: "info.circle", tint: .secondary,
                text: "保修状态与激活/购买日期需向 Apple 服务器查询，本 App 不联网因此无法直接读取。点击下方按钮用序列号在官网查询。")

            HStack(spacing: DS.Spacing.md) {
                Button {
                    if let url = URL(string: "https://checkcoverage.apple.com/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("在 Apple 官网查询保修", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(p.serialNumber, forType: .string)
                } label: {
                    Label("复制序列号", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(p.serialNumber.isEmpty)
            }
        }
    }

    private func cardHeader(icon: String, title: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon).foregroundStyle(.tint).font(.system(size: 13, weight: .semibold))
            SectionLabel(text: title)
            Spacer()
        }
    }

    private func ageText(_ yearStr: String) -> String {
        guard let year = Int(yearStr) else { return "未知" }
        let now = Calendar.current.component(.year, from: Date())
        let age = now - year
        if age <= 0 { return "当年机型（约 1 年内）" }
        return "约 \(age) 年"
    }
}

/// 优雅的键值列表：图标 + 名称在左，值在右，行间发丝分隔。
struct KeyValueList<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
    }
}

struct KVRow: View {
    let icon: String
    let key: String
    let value: String
    var mono: Bool = false
    var copyable: Bool = false
    var valueTint: Color? = nil
    var last: Bool = false

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(key).font(DS.Font.body).foregroundStyle(.secondary)
                Spacer(minLength: DS.Spacing.lg)
                Text(value)
                    .font(mono ? DS.Font.mono : DS.Font.body)
                    .foregroundStyle(valueTint ?? .primary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                if copyable {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("复制")
                }
            }
            .padding(.vertical, DS.Spacing.sm)
            if !last { DS.Divider() }
        }
    }
}

// MARK: - 通用分类详情（电池 / 安全 / 存储 / 网络 / 接口）

struct CategoryDetailView: View {
    @EnvironmentObject private var model: AppModel
    let item: SidebarItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                let results = model.results(for: item)
                if results.isEmpty {
                    if model.isScanning {
                        ProgressView("正在检测…")
                    } else {
                        InlineNotice(icon: "minus.circle", tint: .secondary, text: "本机无此项数据或不适用。")
                    }
                } else {
                    ForEach(results) { result in
                        resultCard(result)
                    }
                }
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(item.title)
    }

    private func resultCard(_ result: CheckResult) -> some View {
        Card {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                Image(systemName: result.status.symbolName)
                    .font(.system(size: 20)).foregroundStyle(result.status.tint)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack(spacing: DS.Spacing.sm) {
                        Text(result.title).font(DS.Font.bodyEmphasis)
                        StatusPill(status: result.status)
                    }
                    Text(result.summary).font(DS.Font.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if let headline = result.isRedFlagHeadline {
                Text(headline)
                    .font(DS.Font.body)
                    .padding(DS.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(Color.red.opacity(0.1)))
            }
            if !result.rawDetails.isEmpty {
                DS.Divider()
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(result.rawDetails.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        InfoRow(key: key, value: value, mono: true)
                    }
                }
            }
        }
    }
}

/// 小型状态药丸标签。
struct StatusPill: View {
    let status: CheckStatus
    var body: some View {
        Text(status.label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 2)
            .background(Capsule().fill(status.tint.opacity(0.15)))
            .foregroundStyle(status.tint)
    }
}

// MARK: - 全屏测试启动面板（键盘 / 屏幕）

struct FullscreenLaunchPane: View {
    @EnvironmentObject private var model: AppModel
    let item: SidebarItem
    let test: FullscreenTest
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                CheckHeader(icon: icon, title: title, subtitle: subtitle)

                if let result = model.result(id: item.resultIDs.first ?? "") {
                    Card {
                        HStack(spacing: DS.Spacing.md) {
                            Image(systemName: result.status.symbolName)
                                .font(.system(size: 20)).foregroundStyle(result.status.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: DS.Spacing.sm) {
                                    Text("上次结果").font(DS.Font.bodyEmphasis)
                                    StatusPill(status: result.status)
                                }
                                Text(result.summary).font(DS.Font.body).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                Button {
                    model.fullscreenTest = test
                } label: {
                    Label(model.result(id: item.resultIDs.first ?? "") == nil ? "开始测试" : "重新测试",
                          systemImage: "play.fill")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                InlineNotice(icon: "info.circle", tint: .secondary,
                    text: "测试将进入全屏。键盘测试期间长按 esc 键、或按 Cmd+Q 可随时安全退出。")
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(title)
    }
}
