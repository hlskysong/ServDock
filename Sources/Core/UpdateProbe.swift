import Foundation

/// 一次版本检测的结果（Sendable，可跨线程传递）
struct UpdateSnapshot: Sendable {
    enum State: String, Sendable {
        /// 还没查过
        case idle
        /// 已是最新
        case upToDate = "up_to_date"
        /// 有新版本
        case available
        /// 查询失败（网络 / 代理 / 仓库还没有 Release）
        case failed
    }

    var state: State = .idle
    var current = Brand.version
    var latest = ""
    var releaseName = ""
    var notes = ""
    var pageURL = ""
    var publishedAt = ""
    var asset: UpdateAsset?
    var checkedAt: Date?
    var error: String?

    var hasUpdate: Bool { state == .available }

    /// 当前构建能不能自己替换自己（开发构建 / 无写权限时不能）
    var canSelfInstall: Bool { UpdateProbe.canSelfInstall }
}

struct UpdateAsset: Sendable, Equatable {
    var name: String
    var url: String
    var size: Int64

    var sizeText: String {
        guard size > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/// 自更新流程的结局
enum UpdateInstallOutcome: Sendable {
    /// 替换脚本已拉起，调用方应该退出应用
    case readyToRestart
    case failed(String)
}

/// 版本检测与自更新。
///
/// 数据来源是 GitHub Releases 的 `/releases/latest`（草稿与预发布默认不返回），
/// 判断依据是 tag 名（`v0.3.0`）与 Info.plist 的 `CFBundleShortVersionString`。
/// 没有任何轮询：应用启动后最多每 24 小时自动查一次，其余靠用户点「检查更新」。
enum UpdateProbe {
    /// 自动检查的最小间隔
    static let autoCheckInterval: TimeInterval = 24 * 3600

    static let lastCheckKey = "servdock.lastUpdateCheck"
    static let skippedKey = "servdock.skippedVersion"

    // MARK: - 查询

    static func fetchLatest() -> UpdateSnapshot {
        var snapshot = UpdateSnapshot()
        snapshot.current = Brand.version
        snapshot.checkedAt = Date()

        var request = URLRequest(url: URL(string: Brand.latestReleaseAPI)!)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(Brand.name)/\(Brand.version)", forHTTPHeaderField: "User-Agent")

        let response = perform(request)
        if let message = response.error {
            snapshot.state = .failed
            snapshot.error = message
            return snapshot
        }
        guard let data = response.data else {
            snapshot.state = .failed
            snapshot.error = L.t("GitHub 没有返回内容")
            return snapshot
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            snapshot.state = .failed
            snapshot.error = L.t("GitHub 返回的内容无法解析")
            return snapshot
        }
        if let message = object["message"] as? String, object["tag_name"] == nil {
            // 典型情况：仓库还没有发布任何 Release
            snapshot.state = .failed
            snapshot.error = message
            return snapshot
        }

        let tag = (object["tag_name"] as? String) ?? ""
        snapshot.latest = normalize(tag)
        snapshot.releaseName = (object["name"] as? String) ?? tag
        snapshot.notes = trimNotes((object["body"] as? String) ?? "")
        snapshot.pageURL = (object["html_url"] as? String) ?? Brand.releasesPage
        snapshot.publishedAt = (object["published_at"] as? String) ?? ""
        snapshot.asset = pickAsset(object["assets"] as? [[String: Any]] ?? [])

        guard !snapshot.latest.isEmpty else {
            snapshot.state = .failed
            snapshot.error = L.t("Release 里没有版本号")
            return snapshot
        }
        snapshot.state = isNewer(snapshot.latest, than: snapshot.current) ? .available : .upToDate
        return snapshot
    }

    /// 优先选 `.zip` 资产（自更新要解包），没有就退回第一个
    private static func pickAsset(_ assets: [[String: Any]]) -> UpdateAsset? {
        guard !assets.isEmpty else { return nil }
        let preferred = assets.first { (($0["name"] as? String) ?? "").hasSuffix(".zip") } ?? assets[0]
        guard let url = preferred["browser_download_url"] as? String else { return nil }
        return UpdateAsset(
            name: (preferred["name"] as? String) ?? "ServDock.zip",
            url: url,
            size: (preferred["size"] as? NSNumber)?.int64Value ?? 0
        )
    }

    private static func trimNotes(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(40)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 阻塞等待的回调只写一次结果：写入一定发生在 `semaphore.signal()` 之前，
    /// 读取发生在 `wait()` 之后，先后关系由信号量保证，所以这里的 @unchecked 是安全的。
    /// 用闭包外层的 `var` 直接存会被判成「mutation of captured var in concurrently-executing code」。
    private final class CallbackResult: @unchecked Sendable {
        var payload: Data?
        var failure: String?
    }

    /// 阻塞式 GET：`error` 非空表示失败，二者必有其一
    private static func perform(_ request: URLRequest) -> (data: Data?, error: String?) {
        let semaphore = DispatchSemaphore(value: 0)
        let result = CallbackResult()

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result.failure = L.t("无法访问 GitHub：%@", error.localizedDescription)
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // 404 基本等于「还没发布过 Release」，别让用户以为是网络问题
                result.failure = http.statusCode == 404
                    ? L.t("还没有发布过版本（仓库未公开或还没有 Release）")
                    : L.t("GitHub 返回 HTTP %d", http.statusCode)
                return
            }
            result.payload = data
        }
        task.resume()

        if semaphore.wait(timeout: .now() + 20) == .timedOut {
            task.cancel()
            return (nil, L.t("请求 GitHub 超时"))
        }
        if let failure = result.failure {
            return (nil, failure)
        }
        guard let payload = result.payload else {
            return (nil, L.t("GitHub 没有返回内容"))
        }
        return (payload, nil)
    }

    // MARK: - 版本比较

    /// 去掉 `v` / `V` 前缀与首尾空白
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        return text
    }

    /// 逐段数字比较：`0.10.0` > `0.9.1`；非数字段（`-beta`）按 0 处理
    static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = segments(lhs)
        let right = segments(rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b ? 1 : -1 }
        }
        return 0
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) > 0
    }

    private static func segments(_ raw: String) -> [Int] {
        normalize(raw)
            .split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
            .map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }

    // MARK: - 自动检查节流

    static var lastCheck: Date? {
        UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }

    static func markChecked(_ date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastCheckKey)
    }

    static var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: skippedKey) }
        set { UserDefaults.standard.set(newValue, forKey: skippedKey) }
    }

    static func isDue(last: Date?) -> Bool {
        guard let last else { return true }
        return Date().timeIntervalSince(last) >= autoCheckInterval
    }

    // MARK: - 自更新

    static var appBundlePath: String { Bundle.main.bundlePath }

    /// 开发构建（`build/ServDock.app`）不去替换自己，避免把编译产物目录搞坏；
    /// 正式构建还要求所在目录对当前用户可写，否则只能引导用户手动下载。
    static var canSelfInstall: Bool {
        let path = appBundlePath
        guard path.hasSuffix(".app") else { return false }
        if path.contains("/build/") { return false }
        let parent = (path as NSString).deletingLastPathComponent
        return FileManager.default.isWritableFile(atPath: parent)
    }

    /// 下载 → 解包 → 校验版本 → 拉起替换脚本。阻塞调用，请放在后台线程。
    static func downloadAndInstall(_ snapshot: UpdateSnapshot) -> UpdateInstallOutcome {
        guard canSelfInstall else {
            return .failed(L.t("当前构建不支持自动替换（开发构建或无写权限），请用发布包的 .zip 手动更新"))
        }
        guard let asset = snapshot.asset else {
            return .failed(L.t("这个 Release 没有可下载的 zip"))
        }

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("ServDock-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            return .failed(L.t("无法创建临时目录：%@", error.localizedDescription))
        }

        let zipURL = workDir.appendingPathComponent(asset.name)
        if let message = download(asset.url, to: zipURL) {
            return .failed(message)
        }

        let extractDir = workDir.appendingPathComponent("extract", isDirectory: true)
        try? fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let unzip = Shell.run("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDir.path], timeout: 90)
        guard unzip.ok else {
            return .failed(L.t("解包失败：%@", Summarize.error(unzip.errorText)))
        }
        guard let newApp = findAppBundle(in: extractDir) else {
            return .failed(L.t("压缩包里没有 ServDock.app"))
        }
        // 防止「下载到的东西和期望版本不符」被直接盖上去
        let newVersion = infoValue(newApp.appendingPathComponent("Contents/Info.plist"), key: "CFBundleShortVersionString")
        guard newVersion.isEmpty || compare(newVersion, snapshot.latest) == 0 else {
            return .failed(L.t("下载包版本是 %@，与 Release 声明的 %@ 不一致", newVersion, snapshot.latest))
        }

        let scriptURL = workDir.appendingPathComponent("install.sh")
        let script = """
        #!/bin/bash
        # shell: bash —— 等待旧进程退出后替换 app bundle，再重新打开
        set -e
        PID="$1"
        TARGET="$2"
        SOURCE="$3"
        WORK="$4"
        for _ in $(seq 1 120); do
            if ! kill -0 "$PID" 2>/dev/null; then break; fi
            sleep 0.25
        done
        sleep 0.4
        rm -rf "$TARGET"
        /usr/bin/ditto "$SOURCE" "$TARGET"
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
        /usr/bin/open "$TARGET"
        # 脚本自己就在 WORK 里，等它读完再删
        ( sleep 2; rm -rf "$WORK" ) >/dev/null 2>&1 &
        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            return .failed(L.t("无法写入更新脚本：%@", error.localizedDescription))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, String(ProcessInfo.processInfo.processIdentifier),
                             appBundlePath, newApp.path, workDir.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failed(L.t("无法启动替换脚本：%@", error.localizedDescription))
        }
        return .readyToRestart
    }

    /// 阻塞式下载；返回非空字符串表示失败原因
    private static func download(_ urlString: String, to target: URL) -> String? {
        guard let url = URL(string: urlString) else {
            return L.t("下载地址不合法：%@", urlString)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("\(Brand.name)/\(Brand.version)", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        let result = CallbackResult()
        let task = URLSession.shared.downloadTask(with: request) { location, response, error in
            defer { semaphore.signal() }
            if let error {
                result.failure = error.localizedDescription
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result.failure = "HTTP \(http.statusCode)"
                return
            }
            guard let location else {
                result.failure = L.t("没有下载到内容")
                return
            }
            do {
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.moveItem(at: location, to: target)
            } catch {
                result.failure = error.localizedDescription
            }
        }
        task.resume()

        if semaphore.wait(timeout: .now() + 180) == .timedOut {
            task.cancel()
            return L.t("下载超时")
        }
        if let failure = result.failure { return L.t("下载失败：%@", failure) }
        return nil
    }

    private static func findAppBundle(in directory: URL) -> URL? {
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if let app = items.first(where: { $0.pathExtension == "app" }) { return app }
            for item in items {
                if let nested = findAppBundle(in: item) { return nested }
            }
        }
        return nil
    }

    private static func infoValue(_ plist: URL, key: String) -> String {
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = object[key] as? String else { return "" }
        return value
    }
}
