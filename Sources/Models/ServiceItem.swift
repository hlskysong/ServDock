import SwiftUI

/// brew services 的原始状态
enum BrewStatus: String, Sendable, CaseIterable {
    case started
    case stopped
    case none
    case error
    case scheduled
    case unknown

    var title: String {
        switch self {
        case .started: return L.t("运行中")
        case .stopped: return L.t("已停止")
        case .none: return L.t("未启动")
        case .error: return L.t("异常")
        case .scheduled: return L.t("定时启动")
        case .unknown: return L.t("未知")
        }
    }

    var isActive: Bool { self == .started }

    var isProblem: Bool { self == .error }

    var color: Color {
        switch self {
        case .started: return Theme.green
        case .stopped, .none: return Theme.textTertiary
        case .error: return Theme.red
        case .scheduled: return Theme.blue
        case .unknown: return Theme.amber
        }
    }
}

/// brew services list --json 的一行
struct BrewServiceEntry: Sendable {
    var name: String
    var status: BrewStatus
    var user: String?
    var file: String?
    var exitCode: Int?
}

/// 合并后的服务条目（静态描述 + 实时状态）
struct ServiceItem: Identifiable, Sendable {
    let spec: ServiceSpec
    var installed: Bool = false
    var version: String?
    var status: BrewStatus = .none
    var user: String?
    var plistPath: String?
    var exitCode: Int?
    var pid: Int?
    var ports: [Int] = []
    /// 默认端口被别的进程占用
    var portConflict: String?
    var loginItem: Bool = false
    var busy: Bool = false
    var busyText: String = ""
    var lastError: String?

    var id: String { spec.id }
    var title: String { spec.title }
    var isRunning: Bool { status.isActive }
    var isInstalled: Bool { installed }

    /// 主要访问地址
    var address: String? {
        guard let port = ports.first ?? (installed ? spec.defaultPort : nil) else { return nil }
        if spec.category == .web { return "http://localhost:\(port)" }
        return "localhost:\(port)"
    }

    var webURL: URL? {
        guard spec.category == .web, let port = ports.first ?? spec.defaultPort else { return nil }
        return URL(string: "http://localhost:\(port)")
    }

    /// Cellar 里真实安装的版本（不含 brew 前缀）
    var versionText: String {
        if let version, !version.isEmpty { return version }
        return isInstalled ? "已安装" : "未安装"
    }

    var portText: String {
        if !ports.isEmpty {
            return ports.map(String.init).joined(separator: ", ")
        }
        if let port = spec.defaultPort {
            return "\(port)"
        }
        return "—"
    }

    /// 只有 brew / 启服托管的服务支持「仅本次启动」
    var supportsRun: Bool { spec.kind != .external }

    /// 打开终端时展示状态的命令
    var statusCommand: String {
        switch spec.kind {
        case .brew: return "brew services info \(id)"
        case .managed: return "launchctl print gui/\(getuid())/\(spec.launchdLabel)"
        case .external: return "sudo launchctl print system/\(spec.launchdLabel)"
        }
    }

    /// 卡片上的托管方式标签（brew 服务不需要额外提示）
    var kindTag: String? {
        switch spec.kind {
        case .brew: return nil
        case .managed: return L.t("启服托管")
        case .external: return L.t("系统服务")
        }
    }
}

/// 可执行的动作
enum ServiceVerb: String, Sendable {
    case start
    case stop
    case restart
    case run

    var doneText: String {
        switch self {
        case .start: return L.t("已启动")
        case .stop: return L.t("已停止")
        case .restart: return L.t("已重启")
        case .run: return L.t("已临时启动")
        }
    }

    var failureText: String {
        switch self {
        case .start: return L.t("启动失败")
        case .stop: return L.t("停止失败")
        case .restart: return L.t("重启失败")
        case .run: return L.t("启动失败")
        }
    }
}

/// 顶部提示
struct ToastMessage: Identifiable, Equatable {
    enum Kind { case success, error, info }

    let id = UUID()
    var kind: Kind
    var text: String

    static func success(_ text: String) -> ToastMessage { .init(kind: .success, text: text) }
    static func error(_ text: String) -> ToastMessage { .init(kind: .error, text: text) }
    static func info(_ text: String) -> ToastMessage { .init(kind: .info, text: text) }
}
