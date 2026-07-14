import SwiftUI

/// 概览页：打开即见。机器档案头部 + 综合评分 + 红旗区 + 各分类状态一览（可点击跳转）。
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                deviceHeader
                if !model.report.redFlags.isEmpty { redFlagSection }
                categorySummary
                testSummary
                footer
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("概览")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.saveCurrentToHistory()
                } label: {
                    Label("保存到历史", systemImage: "square.and.arrow.down")
                }
                .disabled(model.isScanning || model.profile == nil)
                .help("保存本次检测快照，便于日后对比（如电池衰减）")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        ReportExporter.export(profile: model.profile, report: model.report, format: .png)
                    } label: { Label("导出为长图 (PNG)", systemImage: "photo") }
                    Button {
                        ReportExporter.export(profile: model.profile, report: model.report, format: .pdf)
                    } label: { Label("导出为 PDF", systemImage: "doc.richtext") }
                } label: {
                    Label("导出报告", systemImage: "square.and.arrow.up")
                }
                .disabled(model.isScanning)
            }
        }
    }

    // MARK: - 机器档案头部

    private var deviceHeader: some View {
        Card {
            HStack(alignment: .top, spacing: DS.Spacing.lg) {
                Image(systemName: deviceSymbol)
                    .font(.system(size: 46))
                    .foregroundStyle(.tint)
                    .frame(width: 64)
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(model.profile?.marketingName ?? "正在识别机型…")
                        .font(DS.Font.largeTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    if let p = model.profile {
                        Text("\(p.chip) · \(p.memory) · \(p.macOSVersion)")
                            .font(DS.Font.body).foregroundStyle(.secondary)
                        HStack(spacing: DS.Spacing.sm) {
                            metaChip(icon: "barcode", text: p.serialNumber.isEmpty ? "序列号未知" : p.serialNumber)
                            metaChip(icon: "cpu", text: p.architecture)
                            if !p.modelYear.isEmpty {
                                metaChip(icon: "calendar", text: "\(p.modelYear) 年款")
                            }
                        }
                    }
                }
                Spacer(minLength: DS.Spacing.md)
                scoreBadge
            }
        }
    }

    /// 统一的元信息小胶囊，避免旧版三个 Label 直接换行挤在一起。
    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(DS.Font.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.1)))
    }

    private var scoreBadge: some View {
        VStack(spacing: 2) {
            Text("\(model.report.score)")
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(scoreColor)
                .contentTransition(.numericText())
            Text("综合评分").font(DS.Font.caption).foregroundStyle(.secondary)
        }
    }

    private var scoreColor: Color {
        if !model.report.redFlags.isEmpty || model.report.score < 60 { return .red }
        if model.report.score < 90 { return .orange }
        return .green
    }

    private var deviceSymbol: String {
        let name = model.profile?.marketingName ?? ""
        if name.contains("mini") || name.contains("Mac Pro") || name.contains("Studio") { return "macstudio.fill" }
        if name.contains("iMac") { return "desktopcomputer" }
        if name.contains("Air") { return "macbook" }
        return "macbook"
    }

    // MARK: - 红旗区

    private var redFlagSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Label("重大问题 · 请优先阅读", systemImage: "exclamationmark.octagon.fill")
                .font(DS.Font.title).foregroundStyle(.red)
            ForEach(model.report.redFlags) { flag in
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    Text(flag.isRedFlagHeadline ?? flag.summary)
                        .font(DS.Font.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(DS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(Color.red.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(Color.red.opacity(0.25)))
            }
        }
    }

    // MARK: - 分类状态一览

    private var categorySummary: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SectionLabel(text: "系统检测")
            Card {
                ForEach(Array(SidebarItem.autoCategories.enumerated()), id: \.element) { index, item in
                    summaryRow(item)
                    if index < SidebarItem.autoCategories.count - 1 { DS.Divider() }
                }
            }
        }
    }

    private var testSummary: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                SectionLabel(text: "硬件测试")
                Spacer()
                Text("\(model.completedTestCount) / \(SidebarItem.interactiveTests.count) 已测试")
                    .font(DS.Font.caption).foregroundStyle(.secondary)
            }
            Card {
                ForEach(Array(SidebarItem.interactiveTests.enumerated()), id: \.element) { index, item in
                    summaryRow(item)
                    if index < SidebarItem.interactiveTests.count - 1 { DS.Divider() }
                }
            }
        }
    }

    private func summaryRow(_ item: SidebarItem) -> some View {
        Button {
            model.selection = item
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: item.icon).frame(width: 22).foregroundStyle(.tint)
                Text(item.title).font(DS.Font.bodyEmphasis)
                Spacer()
                if let status = model.status(for: item) {
                    Text(model.results(for: item).first?.summary ?? status.label)
                        .font(DS.Font.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail).frame(maxWidth: 320, alignment: .trailing)
                    StatusDot(status: status)
                } else {
                    Text(item.isInteractive ? "未测试" : "—")
                        .font(DS.Font.caption).foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DS.Divider()
            Text("检测时间：\(model.generatedAt.formatted(date: .abbreviated, time: .shortened)) · MacCheck v\(model.report.appVersion)")
            Text("本 App 完全本地运行，不联网、不上传任何数据。检测结果仅供参考，不构成质保。")
        }
        .font(DS.Font.caption).foregroundStyle(.secondary)
        .padding(.top, DS.Spacing.sm)
    }
}
