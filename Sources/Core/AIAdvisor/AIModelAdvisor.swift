import Foundation

/// 单个大模型的可跑性判定。
enum AIVerdict: String, Sendable {
    case smooth   // 流畅
    case runnable // 可跑
    case tight    // 勉强
    case no       // 不建议

    var label: String {
        switch self {
        case .smooth: return L("流畅", "Smooth")
        case .runnable: return L("可跑", "Runs")
        case .tight: return L("勉强", "Tight")
        case .no: return L("不建议", "Not advised")
        }
    }
    var rank: Int {
        switch self {
        case .smooth: return 3
        case .runnable: return 2
        case .tight: return 1
        case .no: return 0
        }
    }
}

struct AIModelSuggestion: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let params: Double        // 十亿参数
    let footprintGB: Double    // Q4 量化 + 少量上下文的显存/内存占用估算
    let verdict: AIVerdict
}

/// 本地大模型可跑性顾问。
/// 判定逻辑核心是**内存**：Apple Silicon 统一内存，GPU/ANE 可共享大部分内存做推理，
/// 内存是决定"能不能跑多大模型"的第一约束。这里给的是保守估算，供参考。
enum AIModelAdvisor {

    /// 留给系统 + App + KV cache 后，可分给模型权重的内存预算（GB）。
    static func budgetGB(ramGB: Double) -> Double {
        max(2, ramGB - 8)
    }

    /// Q4_K_M 量化经验值：约 0.55 GB / 十亿参数，再加 ~1.5GB 上下文与运行时开销。
    static func footprintGB(params: Double) -> Double {
        params * 0.55 + 1.5
    }

    /// 主流开源模型目录（2026，覆盖从小到大的常见档位）。
    static let catalog: [(name: String, params: Double)] = [
        ("Llama 3.2 3B", 3),
        ("Gemma 3 4B", 4),
        ("Qwen3 4B", 4),
        ("Llama 3.1 8B", 8),
        ("Qwen3 8B", 8),
        ("DeepSeek-R1 Distill 8B", 8),
        ("Gemma 3 12B", 12),
        ("Phi-4 14B", 14),
        ("Qwen3 14B", 14),
        ("Mistral Small 24B", 24),
        ("Gemma 3 27B", 27),
        ("Qwen3 32B", 32),
        ("Llama 3.3 70B", 70),
        ("Qwen3 72B", 72),
    ]

    static func suggestions(ramGB: Double) -> [AIModelSuggestion] {
        let budget = budgetGB(ramGB: ramGB)
        return catalog.map { m in
            let fp = footprintGB(params: m.params)
            let verdict: AIVerdict
            if fp <= budget * 0.6 { verdict = .smooth }
            else if fp <= budget * 0.9 { verdict = .runnable }
            else if fp <= budget * 1.1 { verdict = .tight }
            else { verdict = .no }
            return AIModelSuggestion(name: m.name, params: m.params, footprintGB: fp, verdict: verdict)
        }
    }

    /// 推荐的"甜点档"：能流畅或可跑里参数最大的那个。
    static func sweetSpot(ramGB: Double) -> AIModelSuggestion? {
        suggestions(ramGB: ramGB)
            .filter { $0.verdict.rank >= AIVerdict.runnable.rank }
            .max { $0.params < $1.params }
    }

    /// 权威参考站点，供用户自行深入对比。
    static var references: [(title: String, subtitle: String, url: String)] { [
        (L("Ollama 模型库", "Ollama Library"), L("一行命令本地跑，最易上手", "Run models locally with one command; easiest to start"), "https://ollama.com/library"),
        ("LM Studio", L("图形界面本地大模型客户端", "Desktop app for running local LLMs"), "https://lmstudio.ai"),
        ("Hugging Face", L("全球最大的开源模型社区", "The largest open-source model community"), "https://huggingface.co/models"),
        ("Apple MLX", L("Apple Silicon 原生优化推理框架", "Apple's inference framework optimized for Apple Silicon"), "https://github.com/ml-explore/mlx"),
    ] }
}
