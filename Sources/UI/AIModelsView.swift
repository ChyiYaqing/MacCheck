import SwiftUI
import AppKit

/// AI 大模型可跑性建议：按本机内存评估能本地跑哪些主流大模型。
struct AIModelsView: View {
    @EnvironmentObject private var model: AppModel

    private var ramGB: Double {
        guard let mem = model.profile?.memory else { return 0 }
        let digits = mem.filter { $0.isNumber }
        return Double(digits) ?? 0
    }
    private var appleSilicon: Bool {
        model.profile?.architecture.contains("Apple Silicon") ?? false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                CheckHeader(
                    icon: "sparkles",
                    title: L("AI 大模型可跑性", "Can This Mac Run AI Models?"),
                    subtitle: L("AI 时代，本地跑大模型主要看内存。下面按本机内存估算能跑哪些主流开源模型，帮你判断这台机器的 AI 能力。", "Running AI models locally mostly comes down to memory. Based on this Mac's memory, here's which popular open models it can handle.")
                )

                if ramGB <= 0 {
                    InlineNotice(icon: "hourglass", tint: .secondary, text: L("正在读取内存信息…", "Reading memory info…"))
                } else {
                    summaryCard
                    if !appleSilicon { intelNotice }
                    modelListCard
                    referencesCard
                    disclaimer
                }
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(L("AI 大模型", "AI Models"))
    }

    private var summaryCard: some View {
        Card {
            HStack(spacing: DS.Spacing.xl) {
                stat(L("本机内存", "Memory"), String(format: "%.0f GB", ramGB))
                stat(L("芯片", "Chip"), model.profile?.chip ?? "—")
                stat(L("模型内存预算", "Memory for models"), String(format: "≈ %.0f GB", AIModelAdvisor.budgetGB(ramGB: ramGB)))
            }
            if let sweet = AIModelAdvisor.sweetSpot(ramGB: ramGB) {
                DS.Divider()
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "star.fill").foregroundStyle(.orange)
                    Text(L("推荐甜点档：", "Sweet spot:")).font(DS.Font.bodyEmphasis)
                    Text(L("\(sweet.name)（约 \(Int(sweet.footprintGB)) GB，Q4 量化）可本地流畅使用", "\(sweet.name) (about \(Int(sweet.footprintGB)) GB, Q4 quantized) runs smoothly on this Mac"))
                        .font(DS.Font.body).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var intelNotice: some View {
        InlineNotice(icon: "exclamationmark.triangle.fill", tint: .orange,
            text: L("本机为 Intel 芯片，缺少统一内存与强 GPU，本地大模型推理会明显偏慢，建议只尝试 8B 以内的小模型。", "This is an Intel Mac. Without unified memory and a strong GPU, local AI models run noticeably slower. Stick to small models (8B or less)."))
    }

    private var modelListCard: some View {
        Card {
            SectionLabel(text: L("主流模型评估（Q4 量化）", "Popular Models (Q4 quantized)"))
            ForEach(Array(AIModelAdvisor.suggestions(ramGB: ramGB).enumerated()), id: \.element.id) { index, s in
                HStack(spacing: DS.Spacing.md) {
                    Text(s.name).font(DS.Font.body).frame(maxWidth: .infinity, alignment: .leading)
                    Text("≈ \(Int(s.footprintGB)) GB").font(DS.Font.caption).foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    verdictBadge(s.verdict)
                }
                .padding(.vertical, DS.Spacing.xs)
                if index < AIModelAdvisor.catalog.count - 1 { DS.Divider() }
            }
        }
    }

    private func verdictBadge(_ v: AIVerdict) -> some View {
        let tint: Color = {
            switch v {
            case .smooth: return .green
            case .runnable: return .blue
            case .tight: return .orange
            case .no: return .secondary
            }
        }()
        return Text(v.label)
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 52)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.15)))
            .foregroundStyle(tint)
    }

    private var referencesCard: some View {
        Card {
            SectionLabel(text: L("去权威站点自己看 · 对比", "Compare on Trusted Sites"))
            ForEach(Array(AIModelAdvisor.references.enumerated()), id: \.offset) { index, ref in
                Button {
                    if let url = URL(string: ref.url) { NSWorkspace.shared.open(url) }
                } label: {
                    HStack(spacing: DS.Spacing.md) {
                        Image(systemName: "arrow.up.forward.square.fill").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ref.title).font(DS.Font.bodyEmphasis).foregroundStyle(.primary)
                            Text(ref.subtitle).font(DS.Font.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, DS.Spacing.xs)
                if index < AIModelAdvisor.references.count - 1 { DS.Divider() }
            }
        }
    }

    private var disclaimer: some View {
        Text(L("说明：以上为 Q4 量化下的保守估算，实际可跑性还与量化等级、上下文长度、并发占用有关。不是所有模型都适合本地跑，超大模型（如 400B+）需服务器级硬件。", "Note: these are conservative Q4 estimates. Real results also depend on quantization level, context length and what else is running. Not every model suits local use; very large models (400B+) need server-class hardware."))
            .font(DS.Font.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(DS.Font.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .semibold))
        }
    }
}
