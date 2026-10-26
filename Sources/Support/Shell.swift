import Foundation

/// 命令执行结果
struct CommandResult: Sendable {
    var status: Int32 = 0
    var stdout: String = ""
    var stderr: String = ""

    var ok: Bool { status == 0 }

    var trimmedOut: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }

    var errorText: String {
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty { return err }
        let out = trimmedOut
        return out.isEmpty ? L.t("退出状态 %d", status) : String(out.suffix(400))
    }

    static func failure(_ message: String) -> CommandResult {
        CommandResult(status: -1, stdout: "", stderr: message)
    }
}

/// 子进程创建计数（诊断用）
final class SpawnStats: @unchecked Sendable {
    static let shared = SpawnStats()
    private let lock = NSLock()
    private var value = 0

    private init() {}

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func tick() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = 0
        lock.unlock()
    }
}

/// 极简进程执行器：GUI App 拿不到登录 shell 的 PATH，这里自己拼。
enum Shell {
    static let home = NSHomeDirectory()

    /// 子进程创建次数（只用于 `--bench` 量化每轮开销，不影响业务）
    static func spawnCount() -> Int { SpawnStats.shared.count }
    static func resetSpawnCount() { SpawnStats.shared.reset() }

    static let searchPaths: [String] = {
        var paths = [String]()
        paths.append(home + "/.bun/bin")
        paths.append(home + "/.local/share/fnm/aliases/default/bin")
        paths.append("/opt/homebrew/bin")
        paths.append("/opt/homebrew/sbin")
        paths.append("/usr/local/bin")
        paths.append(home + "/.local/bin")
        paths.append(contentsOf: ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
        return paths
    }()

    static let pathEnv = searchPaths.joined(separator: ":")

    static let baseEnv: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = pathEnv
        env["HOME"] = home
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        env["HOMEBREW_NO_EMOJI"] = "1"
        env["NONINTERACTIVE"] = "1"
        env.removeValue(forKey: "HOMEBREW_PREFIX")
        env.removeValue(forKey: "HOMEBREW_CELLAR")
        env.removeValue(forKey: "HOMEBREW_REPOSITORY")
        return env
    }()

    /// brew 可执行文件
    static let brewPath: String? = {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }()

    /// brew 安装前缀（/opt/homebrew）
    static let brewPrefix: String = {
        guard let brew = brewPath else { return "/opt/homebrew" }
        return URL(fileURLWithPath: brew)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }()

    static var cellar: String { brewPrefix + "/Cellar" }

    /// 同步执行命令（后台线程调用）
    static func run(
        _ executable: String,
        _ args: [String] = [],
        timeout: TimeInterval = 90,
        env extraEnv: [String: String] = [:],
        cwd: String? = nil
    ) -> CommandResult {
        SpawnStats.shared.tick()
        let fm = FileManager.default
        let ioDir = fm.temporaryDirectory.appendingPathComponent("ServDock-io", isDirectory: true)
        try? fm.createDirectory(at: ioDir, withIntermediateDirectories: true)
        let token = UUID().uuidString
        let outURL = ioDir.appendingPathComponent(token + ".out")
        let errURL = ioDir.appendingPathComponent(token + ".err")
        fm.createFile(atPath: outURL.path, contents: nil)
        fm.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? fm.removeItem(at: outURL)
            try? fm.removeItem(at: errURL)
        }

        guard let outHandle = try? FileHandle(forWritingTo: outURL),
              let errHandle = try? FileHandle(forWritingTo: errURL) else {
            return .failure(L.t("无法创建临时文件"))
        }

        let process = Process()
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + args
        }
        process.standardOutput = outHandle
        process.standardError = errHandle
        process.standardInput = FileHandle.nullDevice
        var env = baseEnv
        env.merge(extraEnv) { _, new in new }
        process.environment = env
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

        var timedOut = false
        do {
            try process.run()
        } catch {
            try? outHandle.close()
            try? errHandle.close()
            return .failure(L.t("无法启动 %@：%@", executable, error.localizedDescription))
        }

        if timeout > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    timedOut = true
                    process.terminate()
                }
            }
        }

        process.waitUntilExit()
        try? outHandle.close()
        try? errHandle.close()

        let out = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        var err = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        var status = process.terminationStatus
        if timedOut {
            status = -2
            err = L.t("命令超时（%d 秒）\n", Int(timeout)) + err
        }
        return CommandResult(status: status, stdout: out, stderr: err)
    }

    /// 异步包装
    static func runAsync(
        _ executable: String,
        _ args: [String] = [],
        timeout: TimeInterval = 90,
        env: [String: String] = [:],
        cwd: String? = nil
    ) async -> CommandResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<CommandResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Self.run(executable, args, timeout: timeout, env: env, cwd: cwd)
                continuation.resume(returning: result)
            }
        }
    }

    static func which(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        for dir in searchPaths {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}
