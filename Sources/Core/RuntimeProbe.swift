import Foundation

// MARK: - Bun

struct BunInfo: Sendable {
    var installed = false
    var version = ""
    var path = ""
    var binTools: [String] = []
    var globalPackages: [String] = []
    var cacheSize: String = "—"
    var shellConfigured = false
    var shellConfigFile: String?
}

// MARK: - Node (fnm)

struct NodeVersionInfo: Identifiable, Sendable {
    var version: String          // v26.12.1
    var path: String             // .../installation
    var npmVersion: String?
    var size: String?
    var isDefault = false

    var id: String { version }
    var display: String { version.hasPrefix("v") ? String(version.dropFirst()) : version }
}

struct NodeSnapshot: Sendable {
    var fnmInstalled = false
    var fnmVersion = ""
    var fnmPath = ""
    var rootPath = ""
    var versions: [NodeVersionInfo] = []
    var defaultVersion: String?
    var shellConfigured = false
    var shellConfigFile: String?

    static let empty = NodeSnapshot()
}

enum RuntimeProbe {

    // MARK: Bun

    static func bun() -> BunInfo {
        var info = BunInfo()
        let bundled = Shell.home + "/.bun/bin/bun"
        let bunPath: String?
        if FileManager.default.isExecutableFile(atPath: bundled) {
            bunPath = bundled
        } else {
            bunPath = Shell.which("bun")
        }
        guard let path = bunPath else { return info }
        info.installed = true
        info.path = path

        let versionResult = Shell.run(path, ["--version"], timeout: 25)
        info.version = versionResult.ok ? versionResult.trimmedOut : ""

        let binDir = (path as NSString).deletingLastPathComponent
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: binDir) {
            info.binTools = entries
                .filter { !$0.hasPrefix(".") && $0 != "__MACOSX" }
                .sorted()
        }

        let globalModules = Shell.home + "/.bun/install/global/node_modules"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: globalModules) {
            info.globalPackages = entries
                .filter { !$0.hasPrefix(".") }
                .sorted()
        }

        let cacheDir = Shell.home + "/.bun/install/cache"
        if let bytes = Paths.directorySize(cacheDir) {
            info.cacheSize = Paths.humanSize(bytes)
        }

        let shellCheck = detectShellIntegration(keywords: [".bun/bin", "BUN_INSTALL", ".bun"])
        info.shellConfigured = shellCheck.configured
        info.shellConfigFile = shellCheck.file
        return info
    }

    // MARK: fnm / Node

    static func node() -> NodeSnapshot {
        var snap = NodeSnapshot()

        let fnmPath = Shell.which("fnm") ?? (Shell.brewPrefix + "/bin/fnm")
        if FileManager.default.isExecutableFile(atPath: fnmPath) {
            snap.fnmInstalled = true
            snap.fnmPath = fnmPath
            let versionResult = Shell.run(fnmPath, ["--version"], timeout: 25)
            if versionResult.ok {
                snap.fnmVersion = versionResult.trimmedOut
                    .replacingOccurrences(of: "fnm ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let candidates = [
            Shell.home + "/.local/share/fnm",
            Shell.home + "/Library/Application Support/fnm"
        ]
        guard let root = candidates.first(where: { Paths.isDirectory($0 + "/node-versions") }) else {
            return snap
        }
        snap.rootPath = root

        let versionsDir = root + "/node-versions"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: versionsDir)) ?? []
        var versions: [NodeVersionInfo] = []

        for name in names.sorted(by: { $0.compare($1, options: .numeric) == .orderedAscending }) {
            let installation = versionsDir + "/" + name + "/installation"
            guard Paths.isDirectory(installation) else { continue }
            var info = NodeVersionInfo(version: name, path: installation)
            let npmPackage = installation + "/lib/node_modules/npm/package.json"
            if let data = FileManager.default.contents(atPath: npmPackage),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let npmVersion = json["version"] as? String {
                info.npmVersion = npmVersion
            }
            if let bytes = Paths.directorySize(versionsDir + "/" + name) {
                info.size = Paths.humanSize(bytes)
            }
            versions.append(info)
        }

        // default 别名指向
        let aliasPath = root + "/aliases/default"
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: aliasPath) {
            let resolved = destination.hasPrefix("/")
                ? destination
                : (aliasPath as NSString).deletingLastPathComponent + "/" + destination
            if let version = versions.first(where: {
                resolved.hasPrefix($0.path) || resolved.contains("/\($0.version)/")
            }) {
                snap.defaultVersion = version.version
            } else if let match = resolved.split(separator: "/").first(where: { $0.hasPrefix("v") && $0.dropFirst().first?.isNumber == true }) {
                snap.defaultVersion = String(match)
            }
        }
        if snap.defaultVersion == nil, let alias = (try? FileManager.default.destinationOfSymbolicLink(atPath: aliasPath)) {
            for version in versions where alias.contains(version.version) {
                snap.defaultVersion = version.version
                break
            }
        }

        for index in versions.indices {
            versions[index].isDefault = versions[index].version == snap.defaultVersion
        }
        snap.versions = versions

        let shellCheck = detectShellIntegration(keywords: ["fnm env", "fnm", "--use-on-cd"])
        snap.shellConfigured = shellCheck.configured
        snap.shellConfigFile = shellCheck.file
        return snap
    }

    // MARK: Shell 集成检测

    static func detectShellIntegration(keywords: [String]) -> (configured: Bool, file: String?) {
        let files = [
            Shell.home + "/.zshrc",
            Shell.home + "/.zprofile",
            Shell.home + "/.config/fish/config.fish",
            Shell.home + "/.bash_profile",
            Shell.home + "/.profile"
        ]
        for file in files {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            if keywords.contains(where: { content.contains($0) }) {
                return (true, (file as NSString).lastPathComponent)
            }
        }
        return (false, nil)
    }
}
