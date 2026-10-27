import SwiftUI

/// 用于导出（PNG 长图 / PDF）的报告版式。固定宽度、自包含、不依赖交互，便于 ImageRenderer 渲染。
struct ReportDocumentView: View {
    let profile: DeviceProfile?
    let report: MacCheckReport

    private let width: CGFloat = 720

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if !report.redFlags.isEmpty { redFlags }
            resultsTable
            footer
        }
        .padding(32)
        .frame(width: width)
        .background(Color.white)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("MacCheck 验机报告", "MacCheck Inspection Report"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                Text(profile?.marketingName ?? "")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                if let p = profile {
                    Text("\(p.chip) · \(p.memory) · \(p.macOSVersion)")
                        .font(.system(size: 12)).foregroundStyle(.gray)
                    Text(L("序列号 \(p.serialNumber) · \(p.modelIdentifier)", "Serial number \(p.serialNumber) · \(p.modelIdentifier)"))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.gray)
                }
            }
            Spacer()
            VStack(spacing: 2) {
                Text("\(report.score)")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(scoreColor)
                Text(L("综合评分", "Overall score")).font(.system(size: 11)).foregroundStyle(.gray)
            }
        }
    }

    private var scoreColor: Color {
        if !report.redFlags.isEmpty || report.score < 60 { return .red }
        if report.score < 90 { return .orange }
        return .green
    }

    private var redFlags: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("⛔ 重大问题", "⛔ Major Issues")).font(.system(size: 14, weight: .bold)).foregroundStyle(.red)
            ForEach(report.redFlags) { flag in
                Text(flag.isRedFlagHeadline ?? flag.summary)
                    .font(.system(size: 12)).foregroundStyle(.black)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
        }
    }

    private var resultsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("检测明细", "Check Details")).font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                .padding(.bottom, 8)
            ForEach(report.results) { r in
                HStack(alignment: .top, spacing: 8) {
                    Text(r.status.exportGlyph).font(.system(size: 12))
                    Text(r.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                        .frame(width: 110, alignment: .leading)
                    Text(r.summary).font(.system(size: 12)).foregroundStyle(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.vertical, 6)
                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L("检测时间：\(report.generatedAt.formatted(date: .abbreviated, time: .shortened)) · MacCheck v\(report.appVersion)", "Checked: \(report.generatedAt.formatted(date: .abbreviated, time: .shortened)) · MacCheck v\(report.appVersion)"))
            Text(L("本报告由 MacCheck 本地生成，不联网、不上传任何数据。结果仅供参考，不构成质保。", "Generated locally by MacCheck — nothing is sent online or uploaded. Results are for reference only and are not a warranty."))
        }
        .font(.system(size: 10)).foregroundStyle(.gray)
    }
}

extension CheckStatus {
    /// 导出图里用文字符号（避免依赖 SF Symbol 渲染差异）。
    var exportGlyph: String {
        switch self {
        case .pass: return "✅"
        case .warning: return "⚠️"
        case .redFlag: return "⛔"
        case .skipped: return "⏭️"
        case .unsupported: return "➖"
        }
    }
}
