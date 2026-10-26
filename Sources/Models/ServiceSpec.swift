import SwiftUI

/// 服务分类（侧边栏分组）
enum ServiceCategory: String, CaseIterable, Identifiable, Sendable {
    case database
    case web
    case messaging
    case search
    case storage
    case network
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .database: return L.t("数据库")
        case .web: return L.t("Web 服务")
        case .messaging: return L.t("消息与协调")
        case .search: return L.t("搜索与缓存")
        case .storage: return L.t("对象存储")
        case .network: return L.t("网络工具")
        case .other: return L.t("其他服务")
        }
    }

    var symbol: String {
        switch self {
        case .database: return "cylinder.split.1x2"
        case .web: return "network"
        case .messaging: return "arrow.left.arrow.right"
        case .search: return "magnifyingglass.circle"
        case .storage: return "externaldrive.connected.to.line.below"
        case .network: return "globe.asia.australia"
        case .other: return "shippingbox"
        }
    }

    var tint: Color {
        switch self {
        case .database: return Theme.blue
        case .web: return Theme.green
        case .messaging: return Theme.amber
        case .search: return Theme.purple
        case .storage: return Theme.cyan
        case .network: return Theme.teal
        case .other: return Theme.pink
        }
    }
}

/// 服务的托管方式
enum ServiceKind: String, Sendable {
    /// brew services 托管（有 plist，由 brew 生成）
    case brew
    /// brew 装了二进制但没有 service 定义，由启服生成本地 LaunchAgent 托管
    case managed
    /// 系统里已注册的 launchd 服务（如 EasyTier 的系统守护进程），只接管状态与启停
    case external

    var title: String {
        switch self {
        case .brew: return "Homebrew"
        case .managed: return L.t("启服")
        case .external: return L.t("系统服务")
        }
    }
}

/// 一个可管理服务的静态描述（不参与状态更新）
struct ServiceSpec: Identifiable, Hashable, Sendable {
    let id: String              // brew formula 名 / 服务标识
    let title: String
    let summary: String
    let category: ServiceCategory
    let defaultPort: Int?
    let processNames: [String]
    /// 配置文件候选，相对 brew prefix 或以 ~ / 开头
    let configCandidates: [String]
    /// 数据目录候选
    let dataCandidates: [String]
    var note: String? = nil

    // MARK: 托管方式扩展

    var kind: ServiceKind = .brew
    /// brew install 的目标（tap 里的 formula 需要写全路径）
    var installTarget: String? = nil
    /// 无法用 brew 安装时打开的下载页
    var installURL: String? = nil
    /// 可执行文件候选（判断是否已安装）
    var binaries: [String] = []
    /// 版本号来自 App Bundle 的 Info.plist（避免为了读版本把 GUI 拉起来）
    var versionPlist: String? = nil
    /// managed 服务的启动参数（第一个参数之后追加可执行文件自身路径）
    var startArgs: [String] = []
    /// managed 服务的环境变量
    var env: [String: String] = [:]
    /// 控制台 / 管理端口（详情页展示）
    var consolePort: Int? = nil
    /// external 服务的 launchd label
    var daemonLabel: String? = nil
    /// external 服务的 plist
    var daemonPlist: String? = nil
    /// 启停需要管理员授权
    var adminRequired: Bool = false

    // MARK: 派生

    /// launchd 里实际使用的 label
    ///
    /// 改名前的 plist 用的是 `local.servicedock.*`，这些 agent 已经在系统里注册过。
    /// 为了不打断正在跑的服务，以「磁盘上实际存在的 plist」为准来选前缀。
    var launchdLabel: String {
        switch kind {
        case .managed:
            if FileManager.default.fileExists(atPath: legacyManagedPlistPath),
               !FileManager.default.fileExists(atPath: newManagedPlistPath) {
                return Brand.legacyAgentPrefix + id
            }
            return Brand.agentPrefix + id
        case .external: return daemonLabel ?? id
        case .brew: return id
        }
    }

    private var newManagedPlistPath: String {
        Shell.home + "/Library/LaunchAgents/" + Brand.agentPrefix + id + ".plist"
    }

    var legacyManagedPlistPath: String {
        Shell.home + "/Library/LaunchAgents/" + Brand.legacyAgentPrefix + id + ".plist"
    }

    var managedPlistPath: String {
        let fm = FileManager.default
        if fm.fileExists(atPath: newManagedPlistPath) { return newManagedPlistPath }
        if fm.fileExists(atPath: legacyManagedPlistPath) { return legacyManagedPlistPath }
        return newManagedPlistPath
    }

    /// 生效的配置来源
    var effectivePlist: String? {
        switch kind {
        case .managed: return managedPlistPath
        case .external: return daemonPlist
        case .brew: return nil
        }
    }

    func binaryPath() -> String? {
        for raw in binaries {
            let path = raw.hasPrefix("/") ? raw : Paths.resolve(raw)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// 从 Info.plist 读版本（external 服务用，不执行任何二进制）
    func bundleVersion() -> String? {
        guard let versionPlist, let data = FileManager.default.contents(atPath: versionPlist),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    func configPaths() -> [String] {
        configCandidates.flatMap { Paths.resolveConfig($0) }
    }

    func dataPaths() -> [String] {
        dataCandidates.map { Paths.resolve($0) }.filter { Paths.exists($0) }
    }

    var cellarPath: String { Shell.cellar + "/" + id }

    /// JVM 类服务的进程名统一是 java，只能靠端口辅助判断
    var isJavaBased: Bool {
        ["zookeeper", "elasticsearch", "kafka", "hadoop", "hbase", "druid"].contains(id)
    }

    /// 进程名是否属于这个服务
    func matches(command: String) -> Bool {
        let cmd = command.lowercased()
        guard !cmd.isEmpty else { return false }
        // command 可能带完整参数，取第一个词再取文件名，例如
        // /Applications/easytier-gui.app/Contents/MacOS/easytier-gui --config-dir ...
        let first = command.split(separator: " ").first.map(String.init) ?? command
        let exe = (first as NSString).lastPathComponent.lowercased()
        let bare = (command as NSString).lastPathComponent.lowercased()
        return processNames.contains { name in
            let target = name.lowercased()
            guard !target.isEmpty else { return false }
            return cmd.hasPrefix(target)
                || target.hasPrefix(cmd)
                || exe == target
                || bare == target
                || exe.hasPrefix(target)
        }
    }

    /// 这个监听进程是否就是本服务（JVM 服务允许用默认端口佐证）
    func owns(process owner: PortOwner) -> Bool {
        if matches(command: owner.command) { return true }
        if isJavaBased,
           owner.command.lowercased() == "java",
           let port = defaultPort,
           owner.ports.contains(port) {
            return true
        }
        return false
    }
}

/// 路径工具
enum Paths {
    static func resolve(_ raw: String) -> String {
        if raw.hasPrefix("/") { return raw }
        if raw.hasPrefix("~") {
            return (raw as NSString).expandingTildeInPath
        }
        return Shell.brewPrefix + "/" + raw
    }

    /// 配置文件候选：目录会展开成目录下的配置文件
    static func resolveConfig(_ raw: String) -> [String] {
        let path = resolve(raw)
        guard isDirectory(path) else {
            return exists(path) ? [path] : []
        }
        let allowed = ["conf", "toml", "yaml", "yml", "json", "ini", "properties", "cnf", "cfg", "plist"]
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return entries
            .filter { allowed.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .map { path + "/" + $0 }
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    static func launchAgentPath(for formula: String) -> String {
        for prefix in SystemProbe.serviceLabelPrefixes {
            let path = Shell.home + "/Library/LaunchAgents/\(prefix)\(formula).plist"
            if exists(path) { return path }
        }
        return Shell.home + "/Library/LaunchAgents/sh.brew.\(formula).plist"
    }

    static func loginItemExists(for formula: String) -> Bool {
        exists(launchAgentPath(for: formula))
    }

    static func humanSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }

    static func directorySize(_ path: String) -> Int64? {
        guard isDirectory(path) else { return nil }
        let result = Shell.run("/usr/bin/du", ["-sk", path], timeout: 20)
        guard result.ok,
              let kb = result.trimmedOut.split(separator: "\t").first.flatMap({ Int64($0) }) else {
            return nil
        }
        return kb * 1024
    }

    /// 确保目录存在
    @discardableResult
    static func ensureDirectory(_ path: String) -> Bool {
        if isDirectory(path) { return true }
        return (try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)) != nil
    }
}

extension ServiceSpec {
    /// 内置服务清单：只做展示与命令映射，实际安装状态以磁盘为准
    static let catalog: [ServiceSpec] = [
        ServiceSpec(
            id: "redis", title: "Redis", summary: "内存键值数据库", category: .database,
            defaultPort: 6379, processNames: ["redis-server"],
            configCandidates: ["etc/redis.conf"], dataCandidates: ["var/db/redis"],
            note: "默认无密码，可通过 redis-cli 连接"
        ),
        ServiceSpec(
            id: "valkey", title: "Valkey", summary: "Redis 社区分支", category: .database,
            defaultPort: 6379, processNames: ["valkey-server"],
            configCandidates: ["etc/valkey.conf"], dataCandidates: ["var/db/valkey"]
        ),
        ServiceSpec(
            id: "mysql", title: "MySQL", summary: "关系型数据库", category: .database,
            defaultPort: 3306, processNames: ["mysqld"],
            configCandidates: ["etc/my.cnf"], dataCandidates: ["var/mysql"],
            note: "首次启动后可用 mysql -uroot 登录"
        ),
        ServiceSpec(
            id: "mysql@8.4", title: "MySQL 8.4", summary: "LTS 版本关系型数据库", category: .database,
            defaultPort: 3306, processNames: ["mysqld"],
            configCandidates: ["etc/my.cnf"], dataCandidates: ["var/mysql"]
        ),
        ServiceSpec(
            id: "mariadb", title: "MariaDB", summary: "MySQL 兼容分支", category: .database,
            defaultPort: 3306, processNames: ["mariadbd", "mysqld"],
            configCandidates: ["etc/my.cnf"], dataCandidates: ["var/mysql"]
        ),
        ServiceSpec(
            id: "postgresql@17", title: "PostgreSQL 17", summary: "对象关系型数据库", category: .database,
            defaultPort: 5432, processNames: ["postgres"],
            configCandidates: ["var/postgresql@17/postgresql.conf"], dataCandidates: ["var/postgresql@17"]
        ),
        ServiceSpec(
            id: "postgresql@16", title: "PostgreSQL 16", summary: "对象关系型数据库", category: .database,
            defaultPort: 5432, processNames: ["postgres"],
            configCandidates: ["var/postgresql@16/postgresql.conf"], dataCandidates: ["var/postgresql@16"]
        ),
        ServiceSpec(
            id: "mongodb-community", title: "MongoDB", summary: "文档型数据库", category: .database,
            defaultPort: 27017, processNames: ["mongod"],
            configCandidates: ["etc/mongod.conf"],
            dataCandidates: ["var/mongodb", "var/log/mongodb"],
            note: "连接串 mongodb://127.0.0.1:27017，默认无认证"
        ),
        ServiceSpec(
            id: "mongodb-community@8.0", title: "MongoDB 8.0", summary: "文档型数据库（8.0 线）", category: .database,
            defaultPort: 27017, processNames: ["mongod"],
            configCandidates: ["etc/mongod.conf"],
            dataCandidates: ["var/mongodb", "var/log/mongodb"],
            note: "连接串 mongodb://127.0.0.1:27017",
            installTarget: "mongodb/brew/mongodb-community@8.0"
        ),
        ServiceSpec(
            id: "mongodb-community@7.0", title: "MongoDB 7.0", summary: "文档型数据库（7.0 线）", category: .database,
            defaultPort: 27017, processNames: ["mongod"],
            configCandidates: ["etc/mongod.conf"],
            dataCandidates: ["var/mongodb", "var/log/mongodb"],
            note: "连接串 mongodb://127.0.0.1:27017",
            installTarget: "mongodb/brew/mongodb-community@7.0"
        ),
        ServiceSpec(
            id: "nginx", title: "Nginx", summary: "反向代理 / 静态服务", category: .web,
            defaultPort: 8080, processNames: ["nginx"],
            configCandidates: ["etc/nginx/nginx.conf", "etc/nginx/servers", "etc/nginx/conf.d"],
            dataCandidates: ["var/log/nginx"],
            note: "Homebrew 默认监听 8080，站点配置放在 etc/nginx/servers"
        ),
        ServiceSpec(
            id: "httpd", title: "Apache HTTPD", summary: "Apache Web 服务器", category: .web,
            defaultPort: 8080, processNames: ["httpd"],
            configCandidates: ["etc/httpd/httpd.conf"], dataCandidates: ["var/log/httpd"]
        ),
        ServiceSpec(
            id: "caddy", title: "Caddy", summary: "自动 HTTPS 的 Web 服务器", category: .web,
            defaultPort: 80, processNames: ["caddy"],
            configCandidates: ["etc/Caddyfile"], dataCandidates: ["var/lib/caddy"]
        ),
        ServiceSpec(
            id: "zookeeper", title: "ZooKeeper", summary: "分布式协调服务", category: .messaging,
            defaultPort: 2181, processNames: ["zookeeper", "QuorumPeerMain"],
            configCandidates: ["etc/zookeeper/zoo.cfg"], dataCandidates: ["var/lib/zookeeper"]
        ),
        ServiceSpec(
            id: "kafka", title: "Kafka", summary: "分布式消息队列", category: .messaging,
            defaultPort: 9092, processNames: ["kafka.Kafka", "kafka"],
            configCandidates: ["etc/kafka/server.properties"], dataCandidates: ["var/lib/kafka-logs"]
        ),
        ServiceSpec(
            id: "rabbitmq", title: "RabbitMQ", summary: "AMQP 消息队列", category: .messaging,
            defaultPort: 15672, processNames: ["beam.smp", "rabbitmq-server"],
            configCandidates: ["etc/rabbitmq/rabbitmq.conf"], dataCandidates: ["var/lib/rabbitmq"],
            note: "管理后台 http://localhost:15672"
        ),
        ServiceSpec(
            id: "etcd", title: "etcd", summary: "高可用键值存储 / 服务发现", category: .messaging,
            defaultPort: 2379, processNames: ["etcd"],
            configCandidates: ["etc/etcd.conf.yml"], dataCandidates: ["var/lib/etcd"]
        ),
        ServiceSpec(
            id: "elasticsearch", title: "Elasticsearch", summary: "全文检索引擎", category: .search,
            defaultPort: 9200, processNames: ["org.elasticsearch.bootstrap"],
            configCandidates: ["etc/elasticsearch/elasticsearch.yml"], dataCandidates: ["var/lib/elasticsearch"],
            note: "占用内存较高，默认单节点模式"
        ),
        ServiceSpec(
            id: "meilisearch", title: "Meilisearch", summary: "轻量全文检索", category: .search,
            defaultPort: 7700, processNames: ["meilisearch"],
            configCandidates: ["etc/meilisearch.toml"], dataCandidates: ["var/lib/meilisearch"]
        ),
        ServiceSpec(
            id: "memcached", title: "Memcached", summary: "内存缓存服务", category: .search,
            defaultPort: 11211, processNames: ["memcached"],
            configCandidates: [], dataCandidates: []
        ),
        ServiceSpec(
            id: "minio", title: "MinIO", summary: "S3 兼容对象存储", category: .storage,
            defaultPort: 9000, processNames: ["minio"],
            configCandidates: [], dataCandidates: ["var/lib/minio"],
            note: "控制台默认 9001 端口"
        ),
        // RustFS：brew 只装二进制、没有 service 定义，用启服的本地 LaunchAgent 托管
        ServiceSpec(
            id: "rustfs", title: "RustFS", summary: "Rust 编写的 S3 兼容对象存储", category: .storage,
            defaultPort: 9000, processNames: ["rustfs"],
            configCandidates: [],
            dataCandidates: ["~/rustfs/data", "~/Library/Logs/ServDock"],
            note: "S3 端点 9000，控制台 http://127.0.0.1:9001（默认 rustfsadmin / rustfsadmin）",
            kind: .managed,
            installTarget: "rustfs/homebrew-tap/rustfs",
            binaries: ["/opt/homebrew/bin/rustfs", "/usr/local/bin/rustfs", "~/.cargo/bin/rustfs"],
            startArgs: [
                "server",
                "--address", "127.0.0.1:9000",
                "--console-enable",
                "--console-address", "127.0.0.1:9001",
                "~/rustfs/data"
            ],
            env: ["RUSTFS_OBS_LOGGER_LEVEL": "info"],
            consolePort: 9001
        ),
        // EasyTier：官方 GUI 自带系统级守护进程，没有 brew 包
        ServiceSpec(
            id: "easytier", title: "EasyTier", summary: "去中心化 P2P 组网 / 虚拟局域网", category: .network,
            defaultPort: 15999, processNames: ["easytier-gui", "easytier-core"],
            configCandidates: ["~/Library/Application Support/com.kkrainbow.easytier/config.d"],
            dataCandidates: ["~/Library/Logs/com.kkrainbow.easytier"],
            note: "启停需要管理员授权；配置文件是 config.d 下的 TOML；RPC 端口 15999",
            kind: .external,
            installURL: "https://github.com/EasyTier/EasyTier/releases",
            binaries: ["/Applications/easytier-gui.app/Contents/MacOS/easytier-gui"],
            versionPlist: "/Applications/easytier-gui.app/Contents/Info.plist",
            daemonLabel: "easytier-gui",
            daemonPlist: "/Library/LaunchDaemons/easytier-gui.plist",
            adminRequired: true
        )
    ]

    static func spec(for id: String) -> ServiceSpec? {
        catalog.first { $0.id == id }
    }

    /// 未知 formula 的兜底描述
    static func fallback(id: String) -> ServiceSpec {
        ServiceSpec(
            id: id, title: id, summary: "Homebrew 服务", category: .other,
            defaultPort: nil, processNames: [id],
            configCandidates: ["etc/\(id).conf"], dataCandidates: []
        )
    }
}
