import Foundation

/// launchctl 封装：用户域直接调用，系统域走管理员授权
enum Launchctl {

    static var userDomain: String { "gui/\(getuid())" }

    // MARK: - 查询

    struct Entry: Sendable {
        var label: String
        var pid: Int?
        var lastExit: Int?
    }

    /// `launchctl list` 解析（一次拿到 label / pid / 上次退出码）
    static func list() -> [Entry] {
        let result = Shell.run("/bin/launchctl", ["list"], timeout: 25)
        var entries: [Entry] = []
        for line in result.stdout.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let pidText = cols[0].trimmingCharacters(in: .whitespaces)
            let exitText = cols[1].trimmingCharacters(in: .whitespaces)
            let label = cols[2].trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            entries.append(
                Entry(
                    label: label,
                    pid: Int(pidText),
                    lastExit: Int(exitText)
                )
            )
        }
        return entries
    }

    // MARK: - 用户域操作

    @discardableResult
    static func bootstrap(plist: String) -> CommandResult {
        let result = Shell.run("/bin/launchctl", ["bootstrap", userDomain, plist], timeout: 40)
        if result.ok { return result }
        // 已加载时 bootstrap 会报 "service already loaded"，退化成 kickstart
        if result.errorText.contains("already") || result.status == 5 {
            let label = (plist as NSString).lastPathComponent
                .replacingOccurrences(of: ".plist", with: "")
            let retry = Shell.run("/bin/launchctl", ["kickstart", "-k", "\(userDomain)/\(label)"], timeout: 40)
            if retry.ok { return retry }
        }
        return result
    }

    @discardableResult
    static func bootout(label: String) -> CommandResult {
        Shell.run("/bin/launchctl", ["bootout", "\(userDomain)/\(label)"], timeout: 40)
    }

    @discardableResult
    static func kickstart(label: String) -> CommandResult {
        Shell.run("/bin/launchctl", ["kickstart", "-k", "\(userDomain)/\(label)"], timeout: 40)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool, label: String) -> CommandResult {
        Shell.run("/bin/launchctl", [enabled ? "enable" : "disable", "\(userDomain)/\(label)"], timeout: 25)
    }

    // MARK: - 系统域（需要管理员授权）

    /// 用 osascript 提权执行，弹系统密码框
    @discardableResult
    static func runPrivileged(_ command: String) -> CommandResult {
        let result = Shell.run("/usr/bin/osascript", ["-e", privilegedScript(command)], timeout: 120)
        if !result.ok, result.errorText.contains("-128") {
            return .failure("已取消管理员授权")
        }
        return result
    }

    /// 异步版：不阻塞主线程（密码框可能停留很久）
    static func runPrivilegedAsync(_ command: String) async -> CommandResult {
        let result = await Shell.runAsync("/usr/bin/osascript", ["-e", privilegedScript(command)], timeout: 180)
        if !result.ok, result.errorText.contains("-128") {
            return .failure("已取消管理员授权")
        }
        return result
    }

    private static func privilegedScript(_ command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    /// 系统守护进程启停
    static func bootstrapSystem(plist: String) -> CommandResult {
        runPrivileged("/bin/launchctl bootstrap system \(Shell.quote(plist))")
    }

    static func bootstrapSystemAsync(plist: String) async -> CommandResult {
        await runPrivilegedAsync("/bin/launchctl bootstrap system \(Shell.quote(plist))")
    }

    static func bootoutSystem(label: String) -> CommandResult {
        runPrivileged("/bin/launchctl bootout system/\(label)")
    }

    static func bootoutSystemAsync(label: String) async -> CommandResult {
        await runPrivilegedAsync("/bin/launchctl bootout system/\(label)")
    }

    static func kickstartSystem(label: String) -> CommandResult {
        runPrivileged("/bin/launchctl kickstart -k system/\(label)")
    }

    static func kickstartSystemAsync(label: String) async -> CommandResult {
        await runPrivilegedAsync("/bin/launchctl kickstart -k system/\(label)")
    }

    // MARK: - 生成本地 LaunchAgent

    /// 为 managed 服务生成 plist，返回路径
    static func writeAgent(for spec: ServiceSpec) -> String? {
        guard let binary = spec.binaryPath() else { return nil }
        let plistPath = spec.managedPlistPath
        let logDir = Brand.logDir
        Paths.ensureDirectory(logDir)
        let logFile = logDir + "/" + spec.id + ".log"

        var programArguments = [binary]
        programArguments.append(contentsOf: spec.startArgs.map { arg in
            arg.hasPrefix("~") ? (arg as NSString).expandingTildeInPath : arg
        })

        var envDict = spec.env
        envDict["PATH"] = Shell.pathEnv
        envDict["HOME"] = Shell.home

        let argsXML = programArguments
            .map { "<string>\(xmlEscape($0))</string>" }
            .joined(separator: "\n        ")
        let envXML = envDict
            .sorted { $0.key < $1.key }
            .map { "<key>\(xmlEscape($0.key))</key><string>\(xmlEscape($0.value))</string>" }
            .joined(separator: "\n        ")

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(xmlEscape(spec.launchdLabel))</string>
            <key>ProgramArguments</key>
            <array>
                \(argsXML)
            </array>
            <key>EnvironmentVariables</key>
            <dict>
                \(envXML)
            </dict>
            <key>WorkingDirectory</key>
            <string>\(xmlEscape(Shell.home))</string>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>StandardOutPath</key>
            <string>\(xmlEscape(logFile))</string>
            <key>StandardErrorPath</key>
            <string>\(xmlEscape(logFile))</string>
        </dict>
        </plist>
        """

        do {
            try xml.write(toFile: plistPath, atomically: true, encoding: .utf8)
            return plistPath
        } catch {
            return nil
        }
    }

    static func removeAgent(for spec: ServiceSpec) {
        try? FileManager.default.removeItem(atPath: spec.managedPlistPath)
    }

    static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

extension Shell {
    /// shell 单引号转义
    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
