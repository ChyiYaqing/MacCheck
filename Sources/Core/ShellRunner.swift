import Foundation

/// 统一的本地命令执行封装。app 不联网，这是唯一的外部交互面，
/// 所有调用方都应把输出当作"不可信输入"处理（解析失败要降级而不是崩溃）。
enum ShellRunner {
    static func run(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return ""
        }
        // 先读完再等退出：输出超过管道缓冲（64KB，如 system_profiler -json）时，
        // 先 waitUntilExit 会让子进程卡在写管道上，双方互等死锁。
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func run(_ command: String, _ arguments: String...) -> String {
        run(command, arguments)
    }
}
