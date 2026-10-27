import SwiftUI
import Foundation

/// B12：性能压力测试。多核满载计算若干秒，监测热状态（ProcessInfo.thermalState 公开 API，
/// 无需 SMC 私有 key），识别散热异常/降频。给出相对吞吐评分。
@MainActor
final class PerformanceCheckModel: ObservableObject {
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var elapsed: Int = 0
    @Published var opsPerSecond: Double = 0
    @Published var thermalSamples: [ProcessInfo.ThermalState] = []
    @Published var finished = false

    // SMC 精确温度/风扇
    @Published var currentReading: SMCReading?
    @Published var peakTemp: Double?
    @Published var peakRPM: Double?
    @Published var idleReading: SMCReading?   // 压测前的静置读数，用于对比升温

    private let durationSeconds = 15
    private var task: Task<Void, Never>?

    var coreCount: Int { ProcessInfo.processInfo.activeProcessorCount }
    var smcAvailable: Bool { idleReading != nil || currentReading != nil }

    var worstThermal: ProcessInfo.ThermalState {
        thermalSamples.max(by: { $0.severity < $1.severity }) ?? .nominal
    }

    func start() {
        guard !isRunning else { return }
        reset()
        isRunning = true
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func reset() {
        progress = 0; elapsed = 0; opsPerSecond = 0; thermalSamples = []; finished = false
        currentReading = nil; peakTemp = nil; peakRPM = nil
    }

    private func run() async {
        let cores = coreCount
        let total = durationSeconds
        // 记录静置基线温度
        idleReading = await Task.detached { SMCService.snapshot() }.value

        for second in 1...total {
            if Task.isCancelled { break }
            // 每秒并发跑满所有核心一小段计算，测吞吐
            let start = DispatchTime.now()
            let ops = await withTaskGroup(of: Double.self) { group -> Double in
                for _ in 0..<cores {
                    group.addTask { PerformanceCheckModel.busyCompute(iterations: 4_000_000) }
                }
                var sum = 0.0
                for await r in group { sum += r }
                return sum
            }
            let dt = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            _ = ops
            let opsCount = Double(cores) * 4_000_000
            self.opsPerSecond = dt > 0 ? opsCount / dt : 0
            self.thermalSamples.append(ProcessInfo.processInfo.thermalState)

            // 采集 SMC 温度/转速（后台读，避免阻塞）
            let reading = await Task.detached { SMCService.snapshot() }.value
            if let reading {
                self.currentReading = reading
                if let t = reading.maxTemp { self.peakTemp = max(self.peakTemp ?? 0, t) }
                if let r = reading.fanRPMs.max() { self.peakRPM = max(self.peakRPM ?? 0, r) }
            }

            self.elapsed = second
            self.progress = Double(second) / Double(total)
        }
        isRunning = false
        finished = !Task.isCancelled
    }

    /// 纯计算负载（nonisolated，跑在后台线程）。返回一个依赖结果的值防止被优化掉。
    nonisolated static func busyCompute(iterations: Int) -> Double {
        var acc = 0.0
        var x = 1.000001
        for _ in 0..<iterations {
            x = x * 1.0000001 + 0.0000001
            acc += x.squareRoot()
        }
        return acc
    }

    func buildResult() -> CheckResult {
        let worst = worstThermal
        let throttled = worst.severity >= ProcessInfo.ThermalState.serious.severity
        let mops = opsPerSecond / 1_000_000
        var details: [String: String] = [
            L("核心数", "CPU cores"): "\(coreCount)",
            L("压测时长", "Test duration"): L("\(elapsed) 秒", "\(elapsed) s"),
            L("末轮吞吐", "Final-round throughput"): String(format: "%.0f M ops/s", mops),
            L("最高热状态", "Peak thermal state"): worst.label,
        ]
        details[L("热状态采样", "Thermal state samples")] = thermalSamples.map(\.label).joined(separator: " → ")
        if let peakTemp { details[L("满载峰值温度", "Peak temp under load")] = String(format: "%.1f °C", peakTemp) }
        if let idle = idleReading?.maxTemp { details[L("静置温度", "Idle temp")] = String(format: "%.1f °C", idle) }
        if let peakRPM { details[L("风扇峰值转速", "Peak fan speed")] = String(format: "%.0f RPM", peakRPM) }

        let tempSuffix: String = {
            guard let peakTemp else { return "" }
            let rpm = peakRPM.map { String(format: L("，风扇 %.0f RPM", ", fan %.0f RPM"), $0) } ?? ""
            return String(format: L("，满载峰值 %.0f°C", ", peak %.0f°C under load"), peakTemp) + rpm
        }()

        if throttled {
            return CheckResult(id: "performance", title: L("性能压测", "Stress test"), status: .warning,
                summary: L("压测中达到「\(worst.label)」热状态，可能存在散热能力下降或降频，建议检查散热",
                           "Reached \"\(worst.label)\" thermal state during the test. Cooling may be degraded or the CPU may throttle; have the cooling checked") + tempSuffix,
                rawDetails: details)
        }
        return CheckResult(id: "performance", title: L("性能压测", "Stress test"), status: .pass,
            summary: L("满载 \(elapsed) 秒，热状态「\(worst.label)」，散热与性能正常",
                       "Full load for \(elapsed) s, thermal state \"\(worst.label)\". Cooling and performance are normal") + tempSuffix,
            rawDetails: details)
    }
}

extension ProcessInfo.ThermalState {
    var severity: Int {
        switch self {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }
    var label: String {
        switch self {
        case .nominal: return L("正常", "Normal")
        case .fair: return L("轻微升温", "Slightly warm")
        case .serious: return L("偏热", "Hot")
        case .critical: return L("过热", "Overheating")
        @unknown default: return L("未知", "Unknown")
        }
    }
    var tint: Color {
        switch self {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }
}

struct PerformanceCheckView: View {
    @StateObject private var model = PerformanceCheckModel()
    let onComplete: (CheckResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            CheckHeader(
                icon: "gauge.with.dots.needle.67percent",
                title: L("性能压力测试", "Performance Stress Test"),
                subtitle: L("让全部 \(model.coreCount) 个核心满载约 15 秒，实时读取精确温度(°C)与风扇转速(RPM)，监测过热降频。可识别散热硅脂老化、翻新机散热异常。",
                            "Runs all \(model.coreCount) cores at full load for about 15 seconds while reading temperature (°C) and fan speed (RPM) live, to catch overheating and throttling. Helps spot dried-out thermal paste or poor cooling on refurbished Macs.")
            )

            gauge

            if model.finished {
                InlineNotice(icon: model.worstThermal.severity >= 2 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                             tint: model.worstThermal.tint,
                             text: L("最高热状态：\(model.worstThermal.label)。", "Peak thermal state: \(model.worstThermal.label). ") + (model.worstThermal.severity >= 2 ? L("达到偏热及以上，建议关注散热。", "It got hot or worse; keep an eye on cooling.") : L("散热表现良好。", "Cooling looks good.")))
            }

            DS.Divider()

            HStack(spacing: DS.Spacing.md) {
                if model.isRunning {
                    Button(L("停止", "Stop")) { model.cancel() }.buttonStyle(.bordered)
                    ProgressView().controlSize(.small)
                    Text(L("压测中 \(model.elapsed)s…", "Testing \(model.elapsed)s…")).font(DS.Font.caption).foregroundStyle(.secondary)
                } else {
                    Button(model.finished ? L("重新压测", "Run Again") : L("开始压测", "Start Test")) { model.start() }
                        .buttonStyle(.borderedProminent)
                    if model.finished {
                        Button(L("保存结果", "Save Result")) { onComplete(model.buildResult()) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(DS.Spacing.xl)
        .checkPane(L("性能压测", "Stress Test"))
        .onDisappear { model.cancel() }
    }

    private var gauge: some View {
        Card {
            HStack(spacing: DS.Spacing.xl) {
                stat(title: L("进度", "Progress"), value: "\(Int(model.progress * 100))%")
                stat(title: L("吞吐", "Throughput"), value: model.opsPerSecond > 0 ? String(format: "%.0f M/s", model.opsPerSecond / 1_000_000) : "—")
                stat(title: L("当前热状态", "Thermal state"),
                     value: (model.thermalSamples.last ?? .nominal).label,
                     tint: (model.thermalSamples.last ?? .nominal).tint)
                Spacer()
            }
            ProgressView(value: model.progress)

            // SMC 精确温度 / 风扇
            if model.smcAvailable {
                DS.Divider()
                HStack(spacing: DS.Spacing.xl) {
                    stat(title: L("SoC 温度", "SoC temp"),
                         value: model.currentReading?.maxTemp.map { String(format: "%.0f °C", $0) } ?? "—",
                         tint: tempTint(model.currentReading?.maxTemp))
                    if let rpm = model.currentReading?.fanRPMs, !rpm.isEmpty {
                        stat(title: rpm.count > 1 ? L("风扇转速", "Fan speeds") : L("风扇", "Fan"),
                             value: rpm.map { String(format: "%.0f", $0) }.joined(separator: " / ") + " RPM")
                    }
                    if let peak = model.peakTemp {
                        stat(title: L("峰值温度", "Peak temp"), value: String(format: "%.0f °C", peak), tint: tempTint(peak))
                    }
                    Spacer()
                }
            } else if model.isRunning {
                Text(L("本机未提供可读取的 SMC 温度/风扇传感器", "This Mac doesn't expose readable SMC temperature or fan sensors"))
                    .font(DS.Font.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func tempTint(_ t: Double?) -> Color {
        guard let t else { return .primary }
        if t >= 95 { return .red }
        if t >= 85 { return .orange }
        return .green
    }

    private func stat(title: String, value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(DS.Font.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
        }
    }
}
