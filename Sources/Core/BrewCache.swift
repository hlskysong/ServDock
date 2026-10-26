import Foundation

/// `brew --version` / `brew list --versions` 的结果缓存。
///
/// 这两条命令内容几乎不变（只有安装 / 卸载 / 升级时才变），但每条都要 fork 一个
/// ruby 进程、耗时数百毫秒。原来每 4 秒轮询都要各跑一次，一天下来是几万次进程创建；
/// 加上 60 秒缓存后，每轮固定开销从 6 个子进程降到 4 个。
///
/// 安装 / 卸载 / 升级成功后调用 `invalidate()`，下一次采集必然重新执行，
/// 所以界面上版本号不会滞后。
final class BrewCache: @unchecked Sendable {
    static let shared = BrewCache()

    /// 缓存有效期
    static let ttl: TimeInterval = 60

    private struct Entry<T> {
        var value: T
        var at: Date
        var isFresh: Bool { Date().timeIntervalSince(at) < BrewCache.ttl }
    }

    private let lock = NSLock()
    private var versionEntry: Entry<String>?
    private var versionsEntry: Entry<[String: String]>?

    private init() {}

    // MARK: - 取值

    func homebrewVersion(force: Bool = false) -> String {
        lock.lock()
        if !force, let entry = versionEntry, entry.isFresh {
            lock.unlock()
            return entry.value
        }
        lock.unlock()

        let value = SystemProbe.brewHomebrewVersionRaw()

        lock.lock()
        versionEntry = Entry(value: value, at: Date())
        lock.unlock()
        return value
    }

    func installedVersions(force: Bool = false) -> [String: String] {
        lock.lock()
        if !force, let entry = versionsEntry, entry.isFresh {
            lock.unlock()
            return entry.value
        }
        lock.unlock()

        let value = SystemProbe.brewVersionsRaw()

        lock.lock()
        versionsEntry = Entry(value: value, at: Date())
        lock.unlock()
        return value
    }

    // MARK: - 失效

    /// 安装 / 卸载 / 升级之后调用
    func invalidate() {
        lock.lock()
        versionEntry = nil
        versionsEntry = nil
        lock.unlock()
    }
}
