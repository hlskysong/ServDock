import Foundation

/// 监听端口的进程
struct PortOwner: Sendable {
    var pid: Int
    var command: String
    var ports: [Int]
}

/// 进程表里的一个进程
struct RunningProcess: Sendable {
    var pid: Int
    var command: String
}

/// 系统探测：全部只读，命令失败时静默降级
enum SystemProbe {

    // MARK: - Homebrew

    static func brewServices() -> [BrewServiceEntry] {
        guard let brew = Shell.brewPath else { return [] }
        let result = Shell.run(brew, ["services", "list", "--json"], timeout: 60)
        // brew 可能因为不受信任的 tap 报错并以非 0 退出，但 stdout 依然有效
        guard let data = result.stdout.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { dict -> BrewServiceEntry? in
            guard let name = dict["name"] as? String else { return nil }
            let statusRaw = (dict["status"] as? String) ?? "unknown"
            let exitCode: Int?
            if let number = dict["exit_code"] as? NSNumber {
                exitCode = number.intValue
            } else {
                exitCode = nil
            }
            var user = dict["user"] as? String
            if user?.isEmpty == true { user = nil }
            var file = dict["file"] as? String
            if file?.isEmpty == true { file = nil }
            return BrewServiceEntry(
                name: name,
                status: BrewStatus(rawValue: statusRaw) ?? .unknown,
                user: user,
                file: file,
                exitCode: exitCode
            )
        }
    }

    /// formula → 已安装版本（取第一个 keg）。走 60 秒缓存，避免每轮轮询都 fork ruby
    static func brewVersions(force: Bool = false) -> [String: String] {
        BrewCache.shared.installedVersions(force: force)
    }

    /// 真正执行 `brew list --versions`（仅供 BrewCache 调用）
    static func brewVersionsRaw() -> [String: String] {
        guard let brew = Shell.brewPath else { return [:] }
        let result = Shell.run(brew, ["list", "--versions"], timeout: 60)
        var map: [String: String] = [:]
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let name = String(parts[0])
            let version = String(parts[1])
            guard !name.contains(":") , !version.contains(":") else { continue }
            map[name] = version
        }
        return map
    }

    /// Homebrew 版本号（走 60 秒缓存）
    static func brewHomebrewVersion(force: Bool = false) -> String {
        BrewCache.shared.homebrewVersion(force: force)
    }

    /// 真正执行 `brew --version`（仅供 BrewCache 调用）
    static func brewHomebrewVersionRaw() -> String {
        guard let brew = Shell.brewPath else { return "未安装 Homebrew" }
        let result = Shell.run(brew, ["--version"], timeout: 30)
        let lines = result.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        if let line = lines.first(where: { $0.hasPrefix("Homebrew ") }) {
            return line.replacingOccurrences(of: "Homebrew ", with: "")
        }
        return lines.first ?? "Homebrew"
    }

    // MARK: - launchd

    /// brew 服务的 label 前缀：旧版 homebrew.mxcl.*，brew 7+ 用 sh.brew.*
    static let serviceLabelPrefixes = ["homebrew.mxcl.", "sh.brew."]

    /// 全量 label → pid（launchctl list 一次拿完，brew / 自管 / 系统服务共用）
    static func launchdPIDs() -> [String: Int] {
        var map: [String: Int] = [:]
        for entry in Launchctl.list() {
            guard let pid = entry.pid else { continue }
            map[entry.label] = pid
        }
        return map
    }

    /// 进程表（一次 ps 拿全部进程，用于外部服务的存活判断）
    static func processTable() -> [RunningProcess] {
        let result = Shell.run("/bin/ps", ["-Ao", "pid=,command="], timeout: 25)
        guard !result.stdout.isEmpty else { return [] }
        var list: [RunningProcess] = []
        for line in result.stdout.split(separator: "\n") {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            guard let space = trimmed.firstIndex(of: " ") else { continue }
            guard let pid = Int(trimmed[..<space]) else { continue }
            let command = String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty else { continue }
            list.append(RunningProcess(pid: pid, command: command))
        }
        return list
    }

    // MARK: - 端口

    /// 一次 lsof 拿到所有监听端口
    static func listening() -> [PortOwner] {
        let result = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"], timeout: 40)
        guard result.ok || !result.stdout.isEmpty else { return [] }
        var owners: [Int: PortOwner] = [:]
        var order: [Int] = []
        var currentPid = 0
        var currentCommand = ""
        var currentPorts: [Int] = []

        func flush() {
            guard currentPid > 0 else { return }
            var seen = Set<Int>()
            let unique = currentPorts.filter { seen.insert($0).inserted }
            if owners[currentPid] == nil {
                order.append(currentPid)
                owners[currentPid] = PortOwner(pid: currentPid, command: currentCommand, ports: unique)
            } else {
                owners[currentPid]?.ports.append(contentsOf: unique)
                if owners[currentPid]?.command.isEmpty == true {
                    owners[currentPid]?.command = currentCommand
                }
            }
        }

        for line in result.stdout.split(separator: "\n") {
            guard let flag = line.first else { continue }
            switch flag {
            case "p":
                flush()
                currentPid = Int(line.dropFirst()) ?? 0
                currentCommand = ""
                currentPorts = []
            case "c":
                currentCommand = String(line.dropFirst())
            case "n":
                let address = String(line.dropFirst())
                if let portPart = address.split(separator: ":").last, let port = Int(portPart) {
                    currentPorts.append(port)
                }
            default:
                break
            }
        }
        flush()
        return order.compactMap { owners[$0] }
    }

    static func processElapsed(pid: Int) -> String? {
        let result = Shell.run("/bin/ps", ["-o", "etime=", "-p", "\(pid)"], timeout: 10)
        let text = result.trimmedOut
        return text.isEmpty ? nil : text
    }

    // MARK: - 文件

    static func fileSize(_ path: String) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return (attrs[.size] as? NSNumber)?.int64Value
    }

    static func fileModified(_ path: String) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }
}
