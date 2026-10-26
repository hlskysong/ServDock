import Foundation

// MARK: - Docker / OrbStack

struct DockerContainer: Identifiable, Sendable, Equatable {
    var id: String
    var name: String
    var image: String
    var state: String
    var status: String
    var ports: String
    var runningFor: String
    var size: String
    var networks: String

    var shortID: String { id.count > 12 ? String(id.prefix(12)) : id }
    var isRunning: Bool { state == "running" }
    var isPaused: Bool { state == "paused" }

    /// `Exited (0) 2 minutes ago` → `Exited (0)`；运行中的保留 `Up 2 minutes`
    var shortStatus: String {
        if isRunning { return status }
        guard let open = status.firstIndex(of: "("),
              let close = status.firstIndex(of: ")"),
              open < close else { return status }
        let head = status[status.startIndex..<open].trimmingCharacters(in: .whitespaces)
        let code = status[status.index(after: open)..<close]
        return "\(head) (\(code))"
    }

    /// `0.0.0.0:6379->6379/tcp, :::6379->6379/tcp` → `6379→6379`
    var shortPorts: String {
        guard !ports.isEmpty else { return "—" }
        var seen = Set<String>()
        var parts: [String] = []
        for piece in ports.split(separator: ",") {
            let text = piece.trimmingCharacters(in: .whitespaces)
            guard let arrow = text.range(of: "->") else { continue }
            let host = text[text.startIndex..<arrow.lowerBound]
            let guest = text[arrow.upperBound...].split(separator: "/").first.map(String.init) ?? ""
            let port = host.split(separator: ":").last.map(String.init) ?? ""
            let label = port.isEmpty ? guest : "\(port)→\(guest)"
            if seen.insert(label).inserted { parts.append(label) }
        }
        return parts.isEmpty ? ports : parts.joined(separator: ", ")
    }
}

struct DockerImage: Identifiable, Sendable, Equatable {
    var imageID: String
    var repository: String
    var tag: String
    var size: String
    var createdSince: String

    /// 同一个镜像可能有多个 tag，用 repo:tag 做唯一键
    var id: String { repository + ":" + tag }
    var shortID: String {
        let raw = imageID.replacingOccurrences(of: "sha256:", with: "")
        return raw.count > 12 ? String(raw.prefix(12)) : raw
    }
    var hasRepo: Bool { repository != "<none>" && !repository.isEmpty }
    var label: String { hasRepo ? "\(repository):\(tag)" : "<none>:<none>" }
}

struct DockerSnapshot: Sendable {
    var cliPath: String?
    var orbPath: String?
    var orbStatus = ""
    var daemonRunning = false
    var serverVersion = ""
    var engine = ""
    var containers: [DockerContainer] = []
    var images: [DockerImage] = []
    var errorText: String?
    var diskTotal = ""
    var diskReclaimable = ""

    static let empty = DockerSnapshot()

    var installed: Bool { cliPath != nil }
    var runningCount: Int { containers.filter { $0.isRunning }.count }
    var stoppedCount: Int { containers.count - runningCount }

    /// OrbStack 装没装（装了才能一键启动）
    var hasOrb: Bool { orbPath != nil }
    var orbIsRunning: Bool { orbStatus.lowercased() == "running" }
}

/// 容器操作动词。中英文句式差异大，直接给整句，别用模板拼动词。
enum ContainerVerb {
    case start, stop, restart, remove

    func doing(_ name: String) -> String {
        switch self {
        case .start: return L.t("正在启动 %@…", name)
        case .stop: return L.t("正在停止 %@…", name)
        case .restart: return L.t("正在重启 %@…", name)
        case .remove: return L.t("正在删除 %@…", name)
        }
    }

    func done(_ name: String) -> String {
        switch self {
        case .start: return L.t("%@ 已启动", name)
        case .stop: return L.t("%@ 已停止", name)
        case .restart: return L.t("%@ 已重启", name)
        case .remove: return L.t("%@ 已删除", name)
        }
    }

    func failed(_ name: String, _ error: String) -> String {
        switch self {
        case .start: return L.t("启动 %@ 失败：%@", name, error)
        case .stop: return L.t("停止 %@ 失败：%@", name, error)
        case .restart: return L.t("重启 %@ 失败：%@", name, error)
        case .remove: return L.t("删除 %@ 失败：%@", name, error)
        }
    }
}

enum DockerProbe {

    /// GUI App 的 PATH 里常常没有 /usr/local/bin，按候选路径找
    static func cli() -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            Shell.home + "/.orbstack/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/usr/bin/docker"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return Shell.which("docker")
    }

    static func orb() -> String? {
        let candidates = ["/opt/homebrew/bin/orb", "/usr/local/bin/orb", "/usr/bin/orb"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return Shell.which("orb")
    }

    static func orbStatus() -> String {
        guard let orb = orb() else { return "" }
        let result = Shell.run(orb, ["status"], timeout: 10)
        return result.trimmedOut.lowercased()
    }

    static func scan() -> DockerSnapshot {
        var snap = DockerSnapshot()
        snap.cliPath = cli()
        snap.orbPath = orb()
        snap.orbStatus = orbStatus()

        guard let docker = snap.cliPath else {
            snap.errorText = L.t("没有找到 docker 命令")
            return snap
        }

        // daemon 没起时这条会很快失败；超时给短一点，别拖住界面
        let server = Shell.run(docker, ["version", "--format", "{{.Server.Version}}"], timeout: 12)
        if server.ok {
            snap.daemonRunning = true
            snap.serverVersion = server.trimmedOut
            snap.engine = detectEngine(docker)
            snap.containers = containers(docker)
            snap.images = images(docker)
            let df = diskUsage(docker)
            snap.diskTotal = df.total
            snap.diskReclaimable = df.reclaimable
        } else {
            snap.errorText = firstMeaningful(server.errorText)
        }
        return snap
    }

    /// OrbStack / Docker Desktop / colima，靠 info 里的 Name 判断
    private static func detectEngine(_ docker: String) -> String {
        let info = Shell.run(docker, ["info", "--format", "{{.Name}}|{{.OperatingSystem}}"], timeout: 12)
        let text = info.trimmedOut
        let lower = text.lowercased()
        if lower.contains("orbstack") { return "OrbStack" }
        if lower.contains("docker desktop") { return "Docker Desktop" }
        if lower.contains("colima") { return "Colima" }
        if lower.contains("rancher") { return "Rancher Desktop" }
        return text.isEmpty ? "Docker" : "Docker"
    }

    static func containers(_ docker: String) -> [DockerContainer] {
        let result = Shell.run(docker, ["ps", "-a", "--no-trunc", "--format", "{{json .}}"], timeout: 30)
        var list: [DockerContainer] = []
        for line in result.stdout.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            list.append(DockerContainer(
                id: obj["ID"] as? String ?? "",
                name: obj["Names"] as? String ?? "",
                image: obj["Image"] as? String ?? "",
                state: (obj["State"] as? String ?? "").lowercased(),
                status: obj["Status"] as? String ?? "",
                ports: obj["Ports"] as? String ?? "",
                runningFor: obj["RunningFor"] as? String ?? "",
                size: obj["Size"] as? String ?? "",
                networks: obj["Networks"] as? String ?? ""
            ))
        }
        return list.sorted {
            if $0.isRunning != $1.isRunning { return $0.isRunning }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func images(_ docker: String) -> [DockerImage] {
        let result = Shell.run(docker, ["images", "--format", "{{json .}}"], timeout: 30)
        var list: [DockerImage] = []
        for line in result.stdout.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            list.append(DockerImage(
                imageID: obj["ID"] as? String ?? "",
                repository: obj["Repository"] as? String ?? "",
                tag: obj["Tag"] as? String ?? "",
                size: obj["Size"] as? String ?? "",
                createdSince: obj["CreatedSince"] as? String ?? ""
            ))
        }
        return list
    }

    /// docker system df --format json 的字段各版本略有差异，缺就留空
    static func diskUsage(_ docker: String) -> (total: String, reclaimable: String) {
        let result = Shell.run(docker, ["system", "df", "--format", "{{json .}}"], timeout: 20)
        var total = ""
        var reclaim = ""
        for line in result.stdout.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let type = (obj["Type"] as? String ?? "").lowercased()
            guard type == "images" else { continue }
            total = obj["Size"] as? String ?? ""
            let reclaimable = obj["Reclaimable"] as? String ?? ""
            // 形如 "1.2GB (80%)"，括号里是占比，只留尺寸
            reclaim = reclaimable.split(separator: " ").first.map(String.init) ?? reclaimable
        }
        return (total, reclaim)
    }

    // MARK: 动作

    static func start(_ container: DockerContainer) async -> CommandResult {
        await simple(["start", container.id])
    }

    static func stop(_ container: DockerContainer) async -> CommandResult {
        await simple(["stop", container.id])
    }

    static func restart(_ container: DockerContainer) async -> CommandResult {
        await simple(["restart", container.id])
    }

    static func remove(_ container: DockerContainer) async -> CommandResult {
        await simple(["rm", "-f", container.id], timeout: 180)
    }

    static func startOrb() async -> CommandResult {
        guard let orb = orb() else { return .failure(L.t("没有找到 orb 命令")) }
        return await Shell.runAsync(orb, ["start"], timeout: 180)
    }

    static func stopOrb() async -> CommandResult {
        guard let orb = orb() else { return .failure(L.t("没有找到 orb 命令")) }
        return await Shell.runAsync(orb, ["stop"], timeout: 180)
    }

    /// 容器日志（GUI 里展示用，限行数避免爆内存）
    static func logs(_ container: DockerContainer, lines: Int = 200) -> String {
        logs(id: container.id, lines: lines)
    }

    static func logs(id: String, lines: Int = 200) -> String {
        guard let docker = cli() else { return "" }
        let result = Shell.run(docker, ["logs", "--tail", "\(lines)", id], timeout: 25)
        let text = result.stdout + result.stderr
        return firstMeaningful(text)
    }

    private static func simple(_ args: [String], timeout: TimeInterval = 120) async -> CommandResult {
        guard let docker = cli() else { return .failure(L.t("没有找到 docker 命令")) }
        return await Shell.runAsync(docker, args, timeout: timeout)
    }

    private static func firstMeaningful(_ text: String) -> String {
        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.last ?? ""
    }
}
