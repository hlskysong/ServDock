import SwiftUI

// MARK: - 语言

enum Lang: String, CaseIterable, Identifiable, Sendable {
    case zh
    case en

    var id: String { rawValue }
    var label: String { self == .zh ? "简体中文" : "English" }
    var badge: String { self == .zh ? "中" : "EN" }
}

/// 轻量本地化：以中文原文为 key，英文查表。
/// 用中文原文做 key 的好处是视图里 `L.t("启动")` 读起来仍然直白，
/// 缺翻译时自动回落到中文，不会出现空串。
final class L10n: ObservableObject {
    static let shared = L10n()
    static let storageKey = Brand.languageKey

    @Published var lang: Lang {
        didSet {
            UserDefaults.standard.set(lang.rawValue, forKey: Self.storageKey)
            L10n.current = lang
        }
    }

    /// 供 `L.t` 这类静态调用读取（视图刷新由 RootView 的 .id 触发）
    static var current: Lang = .zh

    private init() {
        // 改名前的 key 是 servicedock.language，用户偏好不该丢
        Brand.migrateDefaultsIfNeeded()
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? Lang.zh.rawValue
        let resolved = Lang(rawValue: raw) ?? .zh
        lang = resolved
        L10n.current = resolved
    }

    static func setLanguage(_ lang: Lang) {
        shared.lang = lang
    }
}

enum L {
    static var lang: Lang { L10n.current }
    static var isEnglish: Bool { L10n.current == .en }

    static func t(_ key: String) -> String {
        guard L10n.current == .en else { return key }
        return L10n.en[key] ?? key
    }

    /// 带参数时 key 里用 %@ / %d 占位
    static func t(_ key: String, _ args: CVarArg...) -> String {
        let template = t(key)
        guard !args.isEmpty else { return template }
        return String(format: template, arguments: args)
    }

    /// 复数化的小工具：中文直接返回，英文按数量选单复数
    static func n(_ count: Int, _ zhUnit: String, _ enSingular: String, _ enPlural: String) -> String {
        if L10n.current == .en {
            return "\(count) \(count == 1 ? enSingular : enPlural)"
        }
        return "\(count) \(zhUnit)"
    }
}
