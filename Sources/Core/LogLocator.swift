import Foundation

/// 日志文件定位与读取（只读）
enum LogLocator {
    struct Candidate: Identifiable, Hashable {
        var path: String
        var size: Int64
        var modified: Date?

        var id: String { path }
        var name: String { (path as NSString).lastPathComponent }
        var folder: String { ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent }
        var sizeText: String { Paths.humanSize(size) }
    }

    /// 收集一个服务可能的所有日志文件，按修改时间倒序
    static func candidates(for item: ServiceItem) -> [Candidate] {
        var paths = Set<String>()
        let id = item.id
        let fm = FileManager.default

        // 1. plist 中显式声明的输出路径
        if let plist = item.plistPath, fm.fileExists(atPath: plist),
           let data = fm.contents(atPath: plist),
           let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            for key in ["StandardOutPath", "StandardErrorPath"] {
                if let path = dict[key] as? String, fm.fileExists(atPath: path) {
                    paths.insert(path)
                }
            }
        }

        // 2. brew var/log 下的同名文件与目录
        let varLog = Shell.brewPrefix + "/var/log"
        let direct = varLog + "/" + id + ".log"
        if fm.fileExists(atPath: direct) { paths.insert(direct) }
        collectLogFiles(in: varLog + "/" + id, into: &paths)

        // 3. spec 里声明的日志目录
        for raw in item.spec.dataCandidates where raw.contains("log") {
            collectLogFiles(in: Paths.resolve(raw), into: &paths)
        }

        // 4. ~/Library/Logs/Homebrew/<formula>
        let brewLogs = Shell.home + "/Library/Logs/Homebrew/" + id
        collectLogFiles(in: brewLogs, into: &paths)

        var result: [Candidate] = []
        for path in paths {
            guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let modified = attrs[.modificationDate] as? Date
            result.append(Candidate(path: path, size: size, modified: modified))
        }
        return result.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    private static func collectLogFiles(in directory: String, into paths: inout Set<String>) {
        guard Paths.isDirectory(directory) else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return }
        for entry in entries {
            let full = directory + "/" + entry
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                // 只下钻一层，避免扫太深
                if let children = try? fm.contentsOfDirectory(atPath: full) {
                    for child in children where child.hasSuffix(".log") || child.hasPrefix("out.log") {
                        let nested = full + "/" + child
                        if !Paths.isDirectory(nested) { paths.insert(nested) }
                    }
                }
            } else if entry.hasSuffix(".log") {
                paths.insert(full)
            }
        }
    }

    /// 读取文件尾部
    static func tail(_ path: String, maxBytes: Int = 200_000) -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return L.t("无法读取日志：%@", path)
        }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        handle.seek(toFileOffset: start)
        let data = handle.readDataToEndOfFile()
        if let text = String(data: data, encoding: .utf8) {
            return start > 0 ? L.t("…（仅显示最后 %@）\n", Paths.humanSize(Int64(maxBytes))) + text : text
        }
        return String(data: data, encoding: .isoLatin1) ?? L.t("（无法解码日志内容）")
    }

    /// 读取文本文件（配置文件预览）：大文件取文件头，配置项都在前面
    static func readText(_ path: String, maxBytes: Int = 200_000) -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return L.t("无法读取：%@", path)
        }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        handle.seek(toFileOffset: 0)
        let data = handle.readData(ofLength: maxBytes)
        // 按字节截断可能切坏 UTF-8，用无损解码
        let text = String(decoding: data, as: UTF8.self)
        if size > UInt64(maxBytes) {
            return L.t("…（文件共 %@，仅显示前 %@）\n", Paths.humanSize(Int64(size)), Paths.humanSize(Int64(maxBytes))) + text
        }
        return text
    }
}
