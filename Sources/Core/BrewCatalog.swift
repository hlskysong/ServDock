import Foundation

// MARK: - Homebrew 包

struct BrewPackage: Identifiable, Sendable, Equatable {
    var name: String
    var version: String = ""
    var summary: String = ""
    var installed = false
    var installedVersion: String?
    /// formula / cask
    var kind = "formula"
    var homepage: String = ""

    var id: String { kind + ":" + name }
    var displayVersion: String {
        installedVersion ?? version
    }
}

enum BrewCatalog {

    static var brew: String? { Shell.brewPath }

    // MARK: 已安装

    /// brew list --formula --versions
    static func installedFormulae() -> [BrewPackage] {
        guard let brew else { return [] }
        let result = Shell.run(brew, ["list", "--formula", "--versions"], timeout: 60)
        // brew 可能因不受信任 tap 报错但仍输出有效内容，这里不看退出码
        var list: [BrewPackage] = []
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let name = parts.first, !name.hasPrefix("==>") else { continue }
            // 多版本时 brew 会按空格列出，取第一个作为当前版本
            let version = parts.count > 1 ? parts[1] : ""
            list.append(BrewPackage(name: name, version: version, installed: true,
                                    installedVersion: version, kind: "formula"))
        }
        return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func installedCasks() -> [BrewPackage] {
        guard let brew else { return [] }
        let result = Shell.run(brew, ["list", "--cask", "--versions"], timeout: 60)
        var list: [BrewPackage] = []
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let name = parts.first, !name.hasPrefix("==>") else { continue }
            let version = parts.count > 1 ? parts[1] : ""
            list.append(BrewPackage(name: name, version: version, installed: true,
                                    installedVersion: version, kind: "cask"))
        }
        return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: 搜索

    /// brew search --formula <q>，再批量 brew info 补描述
    static func search(_ query: String, kind: String, limit: Int = 40) -> [BrewPackage] {
        guard let brew else { return [] }
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        let flag = kind == "cask" ? "--cask" : "--formula"
        let searchResult = Shell.run(brew, ["search", flag, keyword], timeout: 90)
        var names: [String] = []
        for line in searchResult.stdout.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.hasPrefix("==>") else { continue }
            // 一行可能有多个名字（brew search 偶尔用空格分隔）
            for token in text.split(separator: " ") where !token.isEmpty {
                let name = String(token)
                if !names.contains(name) { names.append(name) }
            }
        }
        if names.isEmpty, searchResult.trimmedOut.contains("Error") {
            return []
        }
        if names.count > limit { names = Array(names.prefix(limit)) }
        guard !names.isEmpty else { return [] }

        return info(for: names, kind: kind)
    }

    /// 批量取 meta（desc / 版本）
    static func info(for names: [String], kind: String) -> [BrewPackage] {
        guard let brew, !names.isEmpty else {
            return names.map { BrewPackage(name: $0, kind: kind) }
        }
        let jsonFlag = kind == "cask" ? "--cask" : "--formula"
        let result = Shell.run(brew, ["info", "--json=v2", jsonFlag] + names, timeout: 120)
        guard let data = result.stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return names.map { BrewPackage(name: $0, kind: kind) }
        }
        let key = kind == "cask" ? "casks" : "formulae"
        let entries = (root[key] as? [[String: Any]]) ?? []

        var map: [String: BrewPackage] = [:]
        for entry in entries {
            let name = (entry["name"] as? String) ?? (entry["token"] as? String) ?? ""
            guard !name.isEmpty else { continue }
            var pkg = BrewPackage(name: name, kind: kind)
            pkg.summary = (entry["desc"] as? String) ?? ""
            pkg.homepage = (entry["homepage"] as? String) ?? ""
            if let versions = entry["versions"] as? [String: Any] {
                pkg.version = (versions["stable"] as? String) ?? ""
            }
            if let installed = entry["installed"] as? [[String: Any]], let first = installed.first {
                pkg.installed = true
                pkg.installedVersion = (first["version"] as? String) ?? pkg.version
            }
            map[name] = pkg
        }

        // 保持 brew search 的顺序
        return names.map { name in
            var pkg = map[name] ?? BrewPackage(name: name, kind: kind)
            if pkg.installed == false, installedNames(kind: kind).contains(name) {
                pkg.installed = true
            }
            return pkg
        }
    }

    /// 已安装名字集合（用于标记搜索结果）
    static func installedNames(kind: String) -> Set<String> {
        let list = kind == "cask" ? installedCasks() : installedFormulae()
        return Set(list.map { $0.name })
    }

    // MARK: 动作

    static func install(_ package: BrewPackage) async -> CommandResult {
        guard let brew else { return .failure(L.t("未找到 Homebrew")) }
        var args = ["install"]
        if package.kind == "cask" { args.append("--cask") }
        args.append(package.name)
        var result = await Shell.runAsync(brew, args, timeout: 3000)
        // 不受信任的 tap：信任后重试一次
        if !result.ok, let tap = AppModel.untrustedTap(in: result.errorText) {
            let trust = await Shell.runAsync(brew, ["trust", tap], timeout: 120)
            if trust.ok {
                result = await Shell.runAsync(brew, args, timeout: 3000)
            }
        }
        // 装完（无论成败）都让缓存失效，成败都能反映到「已安装」列表上
        BrewCache.shared.invalidate()
        return result
    }

    static func uninstall(_ package: BrewPackage) async -> CommandResult {
        guard let brew else { return .failure(L.t("未找到 Homebrew")) }
        var args = ["uninstall"]
        if package.kind == "cask" { args.append("--cask") }
        args.append(package.name)
        let result = await Shell.runAsync(brew, args, timeout: 600)
        BrewCache.shared.invalidate()
        return result
    }
}
