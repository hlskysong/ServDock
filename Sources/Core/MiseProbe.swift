import Foundation

// MARK: - mise

struct MiseTool: Identifiable, Sendable, Equatable {
    var name: String
    var version: String
    var requested: String
    var installPath: String
    var sourcePath: String
    var installed: Bool
    var active: Bool

    var id: String { name + "@" + version }
}

/// 某个 shell 的 mise 激活情况。
///
/// `mise doctor` 里的 `activated:` 只反映**当前进程**的环境变量，
/// GUI App 拿不到登录 shell 的环境，所以不能拿它判断「用户到底有没有配」。
/// 真正的判据是 shell 启动配置文件里有没有 `mise activate`。
struct ShellActivation: Identifiable, Sendable, Equatable {
    var shell: String
    var files: [String]
    /// 已经写了 mise activate 的那个文件（nil 表示没配）
    var configuredFile: String?
    /// 主配置文件是否已存在
    var exists: Bool

    var id: String { shell }
    var configured: Bool { configuredFile != nil }
}

struct MiseSnapshot: Sendable {
    var installed = false
    var version = ""
    var dataDir = ""
    var configFile: String?
    var shimsOnPath = false
    /// 当前进程环境里是否已激活（`mise doctor` 的 activated，仅作参考）
    var processActivated = false
    var updateAvailable = false
    var tools: [MiseTool] = []
    var activations: [ShellActivation] = []
    var loginShell = ""
    var shimsDirExists = false

    static let empty = MiseSnapshot()

    var toolNames: [String] { Array(Set(tools.map { $0.name })).sorted() }

    /// 任一 shell 配置文件里配了 mise activate，或者当前进程环境已激活
    var activated: Bool {
        processActivated || activations.contains { $0.configured }
    }

    /// 已经配置好的 shell 名字
    var activatedShells: [String] {
        activations.filter { $0.configured }.map { $0.shell }
    }

    /// 登录 shell 对应的激活记录
    var loginActivation: ShellActivation? {
        activations.first { $0.shell == loginShell }
    }
}

struct MiseRegistryEntry: Identifiable, Sendable, Equatable {
    var name: String
    var backends: String
    var summary: String = ""

    var id: String { name }
}

enum MiseProbe {

    static func path() -> String? {
        Shell.which("mise") ?? (Shell.home + "/.local/bin/mise")
    }

    /// 默认数据目录（macOS）
    static var defaultDataDir: String {
        Shell.home + "/.local/share/mise"
    }

    static func scan() -> MiseSnapshot {
        var snap = MiseSnapshot()
        guard let mise = path(), FileManager.default.isExecutableFile(atPath: mise) else {
            return snap
        }
        snap.installed = true

        let versionResult = Shell.run(mise, ["--version"], timeout: 25)
        if versionResult.ok {
            snap.version = versionResult.trimmedOut
                .components(separatedBy: " ").first ?? versionResult.trimmedOut
        }

        let doctor = Shell.run(mise, ["doctor"], timeout: 40)
        if doctor.ok {
            for line in doctor.stdout.split(separator: "\n") {
                let text = line.trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("activated:") {
                    snap.processActivated = text.contains("yes")
                } else if text.hasPrefix("shims_on_path:") {
                    snap.shimsOnPath = text.contains("yes")
                } else if text.hasPrefix("self_update_available:") {
                    snap.updateAvailable = text.contains("yes")
                }
            }
        }

        // 数据目录：优先环境变量，否则看默认路径是否存在
        if let custom = ProcessInfo.processInfo.environment["MISE_DATA_DIR"], !custom.isEmpty {
            snap.dataDir = custom
        } else {
            snap.dataDir = defaultDataDir
        }

        snap.shimsDirExists = FileManager.default.fileExists(atPath: snap.dataDir + "/shims")
        snap.loginShell = loginShell()
        snap.activations = detectActivation()

        // 全局配置文件
        let configCandidates = [
            Shell.home + "/.config/mise/config.toml",
            Shell.home + "/.config/mise.toml",
            Shell.home + "/.mise.toml"
        ]
        snap.configFile = configCandidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? (FileManager.default.fileExists(atPath: Shell.home + "/.config/mise/config.toml")
                ? Shell.home + "/.config/mise/config.toml" : nil)

        snap.tools = tools(mise)
        return snap
    }

    /// mise ls --json
    static func tools(_ mise: String) -> [MiseTool] {
        let result = Shell.run(mise, ["ls", "--json"], timeout: 60)
        guard let data = result.stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var list: [MiseTool] = []
        for (name, value) in root {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                let source = entry["source"] as? [String: Any]
                list.append(MiseTool(
                    name: name,
                    version: (entry["version"] as? String) ?? "",
                    requested: (entry["requested_version"] as? String) ?? "",
                    installPath: (entry["install_path"] as? String) ?? "",
                    sourcePath: (source?["path"] as? String) ?? "",
                    installed: (entry["installed"] as? Bool) ?? false,
                    active: (entry["active"] as? Bool) ?? false
                ))
            }
        }
        return list.sorted {
            if $0.name == $1.name { return $0.version.compare($1.version, options: .numeric) == .orderedDescending }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// mise registry（全量工具名，1067 个左右，只在需要时拉）
    static func registry() -> [MiseRegistryEntry] {
        guard let mise = path() else { return [] }
        let result = Shell.run(mise, ["registry"], timeout: 60)
        var list: [MiseRegistryEntry] = []
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let name = parts.first else { continue }
            let backends = parts.count > 1 ? String(parts[1]) : ""
            list.append(MiseRegistryEntry(name: String(name), backends: backends.trimmingCharacters(in: .whitespaces)))
        }
        return list
    }

    /// mise search <q>，带描述
    static func search(_ query: String, limit: Int = 30) -> [MiseRegistryEntry] {
        guard let mise = path() else { return [] }
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }
        let result = Shell.run(mise, ["search", keyword], timeout: 60)
        var list: [MiseRegistryEntry] = []
        for line in result.stdout.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.hasPrefix("mise ") else { continue }
            let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let name = parts.first else { continue }
            let summary = parts.count > 1 ? String(parts[1]) : ""
            list.append(MiseRegistryEntry(name: String(name), backends: "", summary: summary))
            if list.count >= limit { break }
        }
        return list
    }

    /// mise ls-remote <tool>，最近的版本
    static func remoteVersions(_ tool: String, limit: Int = 40) -> [String] {
        guard let mise = path() else { return [] }
        let result = Shell.run(mise, ["ls-remote", tool], timeout: 120)
        let versions = result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("mise ") }
        return Array(versions.suffix(limit).reversed())
    }

    // MARK: Shell 激活

    /// 登录 shell。GUI 进程里的 `$SHELL` 常是系统默认值，优先问 passwd。
    static func loginShell() -> String {
        if let pw = getpwuid(getuid()), let raw = pw.pointee.pw_shell {
            let path = String(cString: raw)
            if !path.isEmpty { return (path as NSString).lastPathComponent }
        }
        let env = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return (env as NSString).lastPathComponent
    }

    static let supportedShells = ["fish", "zsh", "bash"]

    /// 各 shell 可能写 activate 的地方
    static func candidateFiles(for shell: String) -> [String] {
        let home = Shell.home
        switch shell {
        case "fish":
            var list = [home + "/.config/fish/config.fish"]
            let confd = home + "/.config/fish/conf.d"
            if let items = try? FileManager.default.contentsOfDirectory(atPath: confd) {
                list += items.filter { $0.hasSuffix(".fish") }.sorted().map { confd + "/" + $0 }
            }
            return list
        case "zsh":
            return [home + "/.zshrc", home + "/.zprofile", home + "/.zshenv"]
        case "bash":
            return [home + "/.bashrc", home + "/.bash_profile", home + "/.profile"]
        default:
            return []
        }
    }

    static func detectActivation() -> [ShellActivation] {
        supportedShells.map { shell in
            let files = candidateFiles(for: shell)
            var hit: String?
            for file in files {
                guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
                if text.contains("mise activate") { hit = file; break }
            }
            return ShellActivation(
                shell: shell,
                files: files,
                configuredFile: hit,
                exists: files.contains { FileManager.default.fileExists(atPath: $0) }
            )
        }
    }

    /// 交互式激活用的正确命令。
    ///
    /// `mise activate` **只是把脚本打印到标准输出**，直接敲等于「看了一眼」，
    /// 必须 pipe 给 source（fish）或 eval（zsh / bash）才会真正生效。
    static func activationSnippet(_ shell: String) -> String {
        switch shell {
        case "fish": return "mise activate fish | source"
        case "bash": return "eval \"$(mise activate bash)\""
        default: return "eval \"$(mise activate zsh)\""
        }
    }

    /// 持久化时写哪个文件
    static func activationTarget(_ shell: String) -> String? {
        let home = Shell.home
        switch shell {
        case "fish": return home + "/.config/fish/config.fish"
        case "zsh": return home + "/.zshrc"
        case "bash": return home + "/.bashrc"
        default: return nil
        }
    }

    /// 把 activate 写进 shell 配置（幂等）
    static func writeActivation(_ shell: String) -> CommandResult {
        guard let target = activationTarget(shell) else {
            return .failure(L.t("暂不支持自动写入 %@ 的配置", shell))
        }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true)

        var text = (try? String(contentsOfFile: target, encoding: .utf8)) ?? ""
        if text.contains("mise activate") {
            return CommandResult(status: 0, stdout: L.t("%@ 里已经有 mise activate，未做修改", shorten(target)))
        }
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += "\n# mise（由启服写入）\n" + activationSnippet(shell) + "\n"

        do {
            try text.write(toFile: target, atomically: true, encoding: .utf8)
            return CommandResult(status: 0, stdout: L.t("已写入 %@", shorten(target)))
        } catch {
            return .failure(L.t("写入 %@ 失败：%@", shorten(target), error.localizedDescription))
        }
    }

    static func shorten(_ path: String) -> String {
        path.replacingOccurrences(of: Shell.home, with: "~")
    }

    // MARK: 动作

    static func install(_ tool: String) async -> CommandResult {
        guard let mise = path() else { return .failure(L.t("未找到 mise")) }
        // use -g 会同时写全局配置并立即下载，符合「装了就能用」的预期
        return await Shell.runAsync(mise, ["use", "-g", "--yes", tool], timeout: 1800)
    }

    static func uninstall(_ tool: String) async -> CommandResult {
        guard let mise = path() else { return .failure(L.t("未找到 mise")) }
        return await Shell.runAsync(mise, ["uninstall", tool], timeout: 600)
    }

    static func upgrade(_ tool: String) async -> CommandResult {
        guard let mise = path() else { return .failure(L.t("未找到 mise")) }
        return await Shell.runAsync(mise, ["upgrade", tool], timeout: 1800)
    }

    static func selfUpdate() async -> CommandResult {
        guard let mise = path() else { return .failure(L.t("未找到 mise")) }
        return await Shell.runAsync(mise, ["self-update"], timeout: 900)
    }
}
