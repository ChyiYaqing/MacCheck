import SwiftUI

/// 历史记录：保存过的验机快照列表 + 与本机当前状态的对比（重点看电池衰减）。
struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                if model.history.isEmpty {
                    emptyState
                } else {
                    ForEach(model.history) { snapshot in
                        snapshotCard(snapshot)
                    }
                }
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("历史记录")
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text("还没有保存的验机快照").font(DS.Font.title)
            Text("在「概览」页点右上角的「保存到历史」，即可存下本次检测。日后再测可对比电池循环、健康度、评分的变化。")
                .font(DS.Font.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420)
        .padding(.top, 60)
    }

    private func snapshotCard(_ s: SavedReport) -> some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(s.deviceName).font(DS.Font.bodyEmphasis)
                    Text(s.savedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(DS.Font.caption).foregroundStyle(.secondary)
                    Text("序列号 \(s.serial)").font(DS.Font.mono).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(s.score)").font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(scoreColor(s.score))
                    Text("评分").font(DS.Font.caption).foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    model.deleteHistory(s.id)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("删除此快照")
            }

            DS.Divider()

            // 快照本身的关键指标
            HStack(spacing: DS.Spacing.xl) {
                metric("电池循环", s.batteryCycles.map { "\($0) 次" } ?? "—")
                metric("电池健康", s.batteryHealth ?? "—")
                Spacer()
            }

            // 与当前对比
            if let comparison = comparisonRows(s), !comparison.isEmpty {
                DS.Divider()
                Text("与本机当前对比").font(DS.Font.section).tracking(0.6).foregroundStyle(.secondary)
                ForEach(comparison, id: \.label) { row in
                    HStack {
                        Text(row.label).font(DS.Font.body).foregroundStyle(.secondary)
                        Spacer()
                        Text(row.then).font(DS.Font.body).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                        Text(row.now).font(DS.Font.bodyEmphasis)
                        if let delta = row.delta {
                            Text(delta).font(DS.Font.caption)
                                .foregroundStyle(row.deltaTint)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(row.deltaTint.opacity(0.15)))
                        }
                    }
                }
            }
        }
    }

    private struct Row {
        let label: String
        let then: String
        let now: String
        let delta: String?
        let deltaTint: Color
    }

    /// 只对当前是同一台机器（序列号一致）时做对比。
    private func comparisonRows(_ s: SavedReport) -> [Row]? {
        guard let profile = model.profile, profile.serialNumber == s.serial else { return nil }
        var rows: [Row] = []

        // 评分
        let scoreDelta = model.report.score - s.score
        rows.append(Row(label: "综合评分", then: "\(s.score)", now: "\(model.report.score)",
                        delta: scoreDelta == 0 ? nil : (scoreDelta > 0 ? "+\(scoreDelta)" : "\(scoreDelta)"),
                        deltaTint: scoreDelta >= 0 ? .green : .orange))

        // 电池循环（次数只会增加，涨得多说明用得多）
        if let then = s.batteryCycles, let now = model.currentBatteryCycles() {
            let d = now - then
            rows.append(Row(label: "电池循环", then: "\(then) 次", now: "\(now) 次",
                            delta: d == 0 ? "无变化" : "+\(d) 次",
                            deltaTint: d > 0 ? .orange : .secondary))
        }

        // 电池健康
        if let then = s.batteryHealth, let now = model.currentBatteryHealth() {
            let tp = Int(then.replacingOccurrences(of: "%", with: "")) ?? 0
            let np = Int(now.replacingOccurrences(of: "%", with: "")) ?? 0
            let d = np - tp
            rows.append(Row(label: "电池健康", then: then, now: now,
                            delta: d == 0 ? "无变化" : "\(d)%",
                            deltaTint: d < 0 ? .orange : .green))
        }
        return rows
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(DS.Font.caption).foregroundStyle(.secondary)
            Text(value).font(DS.Font.bodyEmphasis)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score < 60 { return .red }
        if score < 90 { return .orange }
        return .green
    }
}
