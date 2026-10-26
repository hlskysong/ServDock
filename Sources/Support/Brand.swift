import Foundation

/// 品牌与路径常量。
///
/// 项目 2026-10-26 由 ServiceDock / 服务坞 更名为 **ServDock / 启服**。
/// 老用户的本地数据（Application Support 目录、日志目录、LaunchAgent label、
/// UserDefaults key）统一在这里做兼容，不需要用户手动清理。
enum Brand {
    static let name = "ServDock"
    static let cjkName = "启服"
    static let bundleID = "local.aming.servdock"
    static let tagline = "macOS 本地服务与运行时控制台"

    /// 版本号以 Info.plist 为准，命令行/关于页共用
    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.2.0"
    }

    // MARK: - 目录

    static var supportDir: String { Shell.home + "/Library/Application Support/" + name }
    static var legacySupportDir: String { Shell.home + "/Library/Application Support/ServiceDock" }

    static var logDir: String { Shell.home + "/Library/Logs/" + name }
    static var legacyLogDir: String { Shell.home + "/Library/Logs/ServiceDock" }

    // MARK: - LaunchAgent（managed 服务）

    static let agentPrefix = "local.servdock."
    static let legacyAgentPrefix = "local.servicedock."

    /// 是不是本应用生成的 agent（新旧前缀都算）
    static func isAgentLabel(_ label: String) -> Bool {
        label.hasPrefix(agentPrefix) || label.hasPrefix(legacyAgentPrefix)
    }

    // MARK: - UserDefaults

    static let languageKey = "servdock.language"
    static let legacyLanguageKey = "servicedock.language"

    // MARK: - 一次性迁移

    /// 老包名留下的数据目录 / 日志目录，合并到新目录（不覆盖新数据）
    static func migrateLegacyDataIfNeeded() {
        mergeDirectory(from: legacySupportDir, to: supportDir)
        mergeDirectory(from: legacyLogDir, to: logDir)
    }

    /// 语言偏好沿用老 key
    static func migrateDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: languageKey) == nil,
           let legacy = defaults.string(forKey: legacyLanguageKey) {
            defaults.set(legacy, forKey: languageKey)
        }
    }

    private static func mergeDirectory(from source: String, to target: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source),
              let items = try? fm.contentsOfDirectory(atPath: source) else { return }
        try? fm.createDirectory(atPath: target, withIntermediateDirectories: true)
        for item in items {
            let from = source + "/" + item
            let to = target + "/" + item
            // 新目录已经有同名内容就保留新的，绝不覆盖
            guard !fm.fileExists(atPath: to) else { continue }
            try? fm.moveItem(atPath: from, toPath: to)
        }
    }
}
