import Foundation

// MARK: - EasyTier 数据结构

/// easytier-cli peer -o json 的一行
struct ETPeer: Identifiable, Sendable, Equatable {
    var id: String
    var ipv4: String
    var hostname: String
    /// Local / p2p / relay
    var cost: String
    var latency: String
    var lossRate: String
    var rx: String
    var tx: String
    var proto: String
    var natType: String
    var version: String

    var isLocal: Bool { cost.lowercased() == "local" }

    var routeText: String {
        switch cost.lowercased() {
        case "local": return L.t("本机")
        case "p2p": return "p2p"
        case "relay": return L.t("中转")
        default: return cost.isEmpty ? "—" : cost
        }
    }
}

/// easytier-cli node -o json
struct ETNodeInfo: Sendable, Equatable {
    var ipv4 = ""
    var hostname = ""
    var version = ""
    var networkName = ""
    var natType = ""
    var publicIPs: [String] = []
    var listeners: [String] = []

    /// 10.144.144.1/24 → 10.144.144.1
    var bareIPv4: String {
        ipv4.split(separator: "/").first.map(String.init) ?? ipv4
    }
}

struct EasyTierSnapshot: Sendable {
    var cliPath: String?
    var rpcPortal = "127.0.0.1:15999"
    var node: ETNodeInfo?
    var peers: [ETPeer] = []
    var error: String?
    var collectedAt = Date()

    static let empty = EasyTierSnapshot()

    var reachable: Bool { node != nil || !peers.isEmpty }
    var cliReady: Bool { cliPath != nil }

    /// 脱敏版快照：仅用于对外截图 / 文档。
    /// 主机名、网络名、公网 IP、虚拟 IPv4、ring 密钥全部换成占位值，表格结构与列宽保持原样。
    func redacted() -> EasyTierSnapshot {
        var copy = self
        if var info = copy.node {
            if !info.hostname.isEmpty { info.hostname = "my-mac.local" }
            if !info.networkName.isEmpty { info.networkName = "my-network" }
            if !info.ipv4.isEmpty { info.ipv4 = "10.144.144.1/24" }
            info.publicIPs = info.publicIPs.enumerated().map { "203.0.113.\($0.offset + 7)" }
            info.listeners = info.listeners.map(Self.maskListener)
            copy.node = info
        }
        var nextIPv4 = 2
        var peers: [ETPeer] = []
        for (index, peer) in copy.peers.enumerated() {
            var item = peer
            if !item.hostname.isEmpty { item.hostname = item.isLocal ? "my-mac.local" : "node-\(index)" }
            if !item.ipv4.isEmpty {
                if item.isLocal {
                    item.ipv4 = "10.144.144.1"
                } else {
                    item.ipv4 = "10.144.144.\(nextIPv4)"
                    nextIPv4 += 1
                }
            }
            item.id = "peer-\(index)"
            peers.append(item)
        }
        copy.peers = peers
        return copy
    }

    /// 只抹 ring:// 后面的 UUID；wg / ws / tcp / udp 是纯地址，保留
    private static func maskListener(_ raw: String) -> String {
        guard raw.hasPrefix("ring://") else { return raw }
        return "ring://••••••"
    }
}

// MARK: - 探测

enum EasyTierProbe {
    /// 启服缓存的 CLI 目录
    static var binDir: String {
        Brand.supportDir + "/bin"
    }

    static let cliName = "easytier-cli"

    /// 按优先级查找 easytier-cli
    static func findCLI() -> String? {
        let candidates = [
            binDir + "/" + cliName,
            "/opt/homebrew/bin/" + cliName,
            "/usr/local/bin/" + cliName,
            "/Applications/easytier-gui.app/Contents/MacOS/" + cliName,
            "/Applications/EasyTier.app/Contents/MacOS/" + cliName,
            Shell.home + "/.cargo/bin/" + cliName
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return Shell.which(cliName)
    }

    /// 从 launchd plist 里读 --rpc-portal（EasyTier 的 GUI 守护进程不一定用默认端口）
    static func rpcPortal() -> String {
        let plists = [
            "/Library/LaunchDaemons/easytier-gui.plist",
            Shell.home + "/Library/LaunchAgents/easytier-gui.plist",
            "/Library/LaunchDaemons/com.kkrainbow.easytier.plist"
        ]
        for path in plists {
            guard let data = FileManager.default.contents(atPath: path),
                  let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { continue }
            let args = (dict["ProgramArguments"] as? [String]) ?? []
            if let index = args.firstIndex(of: "--rpc-portal"), index + 1 < args.count {
                return args[index + 1]
            }
        }
        // 默认端口 15888，GUI 守护进程用 15999
        return "127.0.0.1:15888"
    }

    static func scan() -> EasyTierSnapshot {
        var snap = EasyTierSnapshot()
        snap.rpcPortal = rpcPortal()
        guard let cli = findCLI() else {
            snap.error = "cli-missing"
            return snap
        }
        snap.cliPath = cli

        let peerResult = Shell.run(cli, ["-p", snap.rpcPortal, "-o", "json", "peer"], timeout: 20)
        guard peerResult.ok, let peerData = peerResult.stdout.data(using: .utf8) else {
            snap.error = Summarize.firstMeaningful(peerResult.errorText) ?? L.t("无法连接")
            return snap
        }
        snap.peers = parsePeers(peerData)

        let nodeResult = Shell.run(cli, ["-p", snap.rpcPortal, "-o", "json", "node"], timeout: 20)
        if nodeResult.ok, let nodeData = nodeResult.stdout.data(using: .utf8) {
            snap.node = parseNode(nodeData)
        } else if snap.node == nil {
            snap.node = nil
        }
        return snap
    }

    static func parsePeers(_ data: Data) -> [ETPeer] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return raw.compactMap { dict in
            guard let ipv4 = dict["ipv4"] as? String else { return nil }
            return ETPeer(
                id: (dict["id"] as? String) ?? ipv4,
                ipv4: ipv4,
                hostname: (dict["hostname"] as? String) ?? "",
                cost: (dict["cost"] as? String) ?? "",
                latency: (dict["lat_ms"] as? String) ?? "-",
                lossRate: (dict["loss_rate"] as? String) ?? "-",
                rx: (dict["rx_bytes"] as? String) ?? "-",
                tx: (dict["tx_bytes"] as? String) ?? "-",
                proto: (dict["tunnel_proto"] as? String) ?? "-",
                natType: (dict["nat_type"] as? String) ?? "-",
                version: (dict["version"] as? String) ?? ""
            )
        }
    }

    static func parseNode(_ data: Data) -> ETNodeInfo? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var node = ETNodeInfo()
        node.ipv4 = (dict["ipv4_addr"] as? String) ?? ""
        node.hostname = (dict["hostname"] as? String) ?? ""
        node.version = (dict["version"] as? String) ?? ""
        node.listeners = (dict["listeners"] as? [String]) ?? []

        if let config = dict["config"] as? String {
            for line in config.split(separator: "\n") where line.contains("network_name") {
                if let value = line.split(separator: "\"").dropFirst().first {
                    node.networkName = String(value)
                }
            }
        }
        if let stun = dict["stun_info"] as? [String: Any] {
            node.publicIPs = (stun["public_ip"] as? [String]) ?? []
            if let type = stun["udp_nat_type"] as? Int {
                node.natType = natName(type)
            }
        }
        return node
    }

    /// EasyTier 的 NatType 枚举值
    static func natName(_ raw: Int) -> String {
        switch raw {
        case 0: return "Unknown"
        case 1: return "OpenInternet"
        case 2: return "NoPAT"
        case 3: return "FullCone"
        case 4: return "Restricted"
        case 5: return "PortRestricted"
        case 6: return "Symmetric"
        case 7: return "SymUdpFirewall"
        case 8: return "SymmetricEasyInc"
        case 9: return "SymmetricEasyDec"
        default: return "Unknown"
        }
    }

    // MARK: CLI 安装

    /// 下载 easytier-cli 到启服缓存目录（从 GitHub release）
    enum InstallResult {
        case success(String)
        case failure(String)
    }

    static func installCLI() -> InstallResult {
        // 1. 找最新版本
        let api = Shell.run("/usr/bin/curl", ["-sL", "--max-time", "30",
            "https://api.github.com/repos/EasyTier/EasyTier/releases/latest"], timeout: 40)
        guard api.ok,
              let data = api.stdout.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = dict["tag_name"] as? String else {
            return .failure(L.t("无法获取 EasyTier 版本信息，请检查网络"))
        }
        let machine = Shell.run("/usr/bin/uname", ["-m"], timeout: 10).trimmedOut
        let arch = machine == "x86_64" ? "x86_64" : "aarch64"
        guard let assets = dict["assets"] as? [[String: Any]],
              let asset = assets.first(where: {
                  let name = ($0["name"] as? String) ?? ""
                  return name.contains("macos-\(arch)") && name.hasSuffix(".zip")
              }),
              let url = asset["browser_download_url"] as? String else {
            return .failure(L.t("找不到适用于本机的 EasyTier 安装包"))
        }

        // 2. 下载到临时目录
        try? FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        let tmpZip = NSTemporaryDirectory() + "easytier-\(tag).zip"
        let tmpDir = NSTemporaryDirectory() + "easytier-\(tag)"
        try? FileManager.default.removeItem(atPath: tmpZip)
        try? FileManager.default.removeItem(atPath: tmpDir)

        let download = Shell.run("/usr/bin/curl", ["-sL", "--max-time", "600", "-o", tmpZip, url], timeout: 640)
        guard download.ok, FileManager.default.fileExists(atPath: tmpZip) else {
            return .failure(L.t("下载失败，请检查网络或代理"))
        }

        // 3. 解压并挑出 CLI
        let unzip = Shell.run("/usr/bin/unzip", ["-o", "-q", tmpZip, "-d", tmpDir], timeout: 180)
        guard unzip.ok else {
            return .failure(L.t("解压失败：%@", Summarize.firstMeaningful(unzip.errorText) ?? ""))
        }
        let target = binDir + "/" + cliName
        guard let found = findFile(named: cliName, in: tmpDir) else {
            return .failure(L.t("压缩包里没有 easytier-cli"))
        }
        try? FileManager.default.removeItem(atPath: target)
        do {
            try FileManager.default.copyItem(atPath: found, toPath: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target)
        } catch {
            return .failure(L.t("写入失败：%@", error.localizedDescription))
        }

        try? FileManager.default.removeItem(atPath: tmpZip)
        try? FileManager.default.removeItem(atPath: tmpDir)
        return .success(target)
    }

    private static func findFile(named name: String, in directory: String) -> String? {
        let enumerator = FileManager.default.enumerator(atPath: directory)
        while let relative = enumerator?.nextObject() as? String {
            if (relative as NSString).lastPathComponent == name {
                return directory + "/" + relative
            }
        }
        return nil
    }
}
