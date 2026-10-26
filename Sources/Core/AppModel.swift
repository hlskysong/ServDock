import AppKit
import SwiftUI

/// 一次采集得到的系统快照（Sendable，跨线程传递安全）
struct SystemSnapshot: Sendable {
    var services: [BrewServiceEntry] = []
    var versions: [String: String] = [:]
    var launchd: [String: Int] = [:]
    var portOwners: [PortOwner] = []
    var processes: [RunningProcess] = []
    var processPIDs: [String: Int] = [:]
    var bun = BunInfo()
    var node = NodeSnapshot.empty
    var brewVersion = ""
    var brewPrefix = ""
    var timestamp = Date()
}

enum NavItem: Hashable {
    case overview
    case category(ServiceCategory)
    case docker
    case timers
    case bun
    case node
    case easytier
    case packages
    case mise
    case settings
}

enum BrewPackagesTab: String, CaseIterable {
    case search
    case installed

    var title: String {
        switch self {
        case .search: return L.t("搜索")
        case .installed: return L.t("已安装")
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [ServiceItem] = []
    @Published var bun = BunInfo()
    @Published var node = NodeSnapshot.empty
    @Published var selection: NavItem = .overview
    @Published var searchText = ""
    @Published var isRefreshing = false
    @Published var lastRefresh: Date?
    @Published var toast: ToastMessage?
    @Published var inspecting: String?
    @Published var brewVersionText = ""
    @Published var installSheet: String?
    @Published var nodeInstallSheet = false
    @Published var showOnlyRunning = false
    @Published var runtimeBusy: String?
    /// 定时任务
    @Published var timers = TimerSnapshot()
    @Published var timersLoading = false
    @Published var timerScopeFilter: TimerScopeFilter = .all
    @Published var timerBusy: String?
    /// 截图模式：不自动重扫定时任务，避免沙箱限制污染截图
    var snapshotMode = false
    @Published var timerLogJob: LaunchdJob?

    // MARK: EasyTier

    @Published var easyTier = EasyTierSnapshot.empty
    @Published var etBusy: String?
    @Published var etRefreshing = false
    @Published var etCliInstalling = false

    // MARK: Homebrew 包

    @Published var brewTab: BrewPackagesTab = .search
    @Published var brewKind = "formula"
    @Published var brewResults: [BrewPackage] = []
    @Published var brewInstalled: [BrewPackage] = []
    @Published var brewSearching = false
    @Published var brewLoading = false
    @Published var brewBusy: String?
    @Published var brewLastQuery = ""

    // MARK: mise

    @Published var mise = MiseSnapshot.empty
    @Published var miseLoading = false
    @Published var miseSearching = false
    @Published var miseSearchResults: [MiseRegistryEntry] = []
    @Published var miseBusy: String?
    @Published var miseActivating: String?
    @Published var miseVersionSheet: String?

    // MARK: Docker / OrbStack

    @Published var docker = DockerSnapshot.empty
    @Published var dockerLoading = false
    @Published var dockerBusy: String?
    @Published var dockerSheet: DockerContainer?
    @Published var dockerTab: DockerTab = .containers

    enum DockerTab: String, CaseIterable {
        case containers
        case images

        var title: String {
            switch self {
            case .containers: return L.t("容器")
            case .images: return L.t("镜像")
            }
        }
    }

    // MARK: 语言

    @Published var lang: Lang = L10n.current

    // MARK: 版本更新

    @Published var update = UpdateSnapshot()
    @Published var updateChecking = false
    @Published var updateInstalling = false
    /// 用户选择了「跳过此版本」
    @Published var updateSkipped = false

    enum TimerScopeFilter: String, CaseIterable, Identifiable {
        case all
        case timed
        case agents
        case cron

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return L.t("全部")
            case .timed: return L.t("定时触发")
            case .agents: return L.t("常驻 / 登录")
            case .cron: return "cron"
            }
        }
    }

    private var refreshLoop: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    /// 运行时探测（bun / fnm / du）开销大，低频执行
    private var lastRuntimeProbe: Date?

    // MARK: - 轮询节流

    /// 窗口在前台且可见时的轮询间隔
    nonisolated static let foregroundInterval: TimeInterval = 4
    /// 主窗口关掉 / 最小化 / 应用失焦时的轮询间隔
    nonisolated static let backgroundInterval: TimeInterval = 30

    /// 当前生效的轮询间隔（设置页展示用）
    @Published private(set) var pollInterval: TimeInterval = AppModel.foregroundInterval

    /// 正在进行的等待，可被 wake() 打断
    private var wakeSignal: Task<Void, Never>?
    private var activityObservers: [NSObjectProtocol] = []

    init(autoStart: Bool = true) {
        if autoStart { start() }
    }

    // MARK: - 采集

    nonisolated static func collectSync(runtimes: Bool = true) -> SystemSnapshot {
        var snap = SystemSnapshot()
        snap.brewPrefix = Shell.brewPrefix
        snap.brewVersion = SystemProbe.brewHomebrewVersion()
        snap.services = SystemProbe.brewServices()
        snap.versions = SystemProbe.brewVersions()
        snap.launchd = SystemProbe.launchdPIDs()
        snap.portOwners = SystemProbe.listening()
        snap.processes = SystemProbe.processTable()

        var specs = ServiceSpec.catalog
        let known = Set(specs.map { $0.id })
        for entry in snap.services where !known.contains(entry.name) {
            specs.append(ServiceSpec.fallback(id: entry.name))
        }
        for spec in specs {
            // 1. launchd 最可靠
            if let pid = launchdPID(for: spec, in: snap) {
                snap.processPIDs[spec.id] = pid
                continue
            }
            // 2. 监听进程的进程名匹配
            if let owner = snap.portOwners.first(where: { spec.owns(process: $0) }) {
                snap.processPIDs[spec.id] = owner.pid
                continue
            }
            // 3. 非 brew 服务（系统守护进程）走进程表兜底
            if spec.kind != .brew,
               let process = snap.processes.first(where: { spec.matches(command: $0.command) }) {
                snap.processPIDs[spec.id] = process.pid
            }
        }
        if runtimes {
            snap.bun = RuntimeProbe.bun()
            snap.node = RuntimeProbe.node()
        }
        return snap
    }

    nonisolated static func collect(runtimes: Bool = true) async -> SystemSnapshot {
        await Task.detached(priority: .userInitiated) { collectSync(runtimes: runtimes) }.value
    }

    /// brew 新版 label 是 sh.brew.*，旧版是 homebrew.mxcl.*，两种都认
    nonisolated static func launchdPID(for spec: ServiceSpec, in snap: SystemSnapshot) -> Int? {
        if let pid = snap.launchd[spec.launchdLabel] { return pid }
        for prefix in SystemProbe.serviceLabelPrefixes {
            if let pid = snap.launchd[prefix + spec.id] { return pid }
        }
        return nil
    }

    func start() {
        guard refreshLoop == nil else { return }
        observeActivity()
        refreshLoop = Task { [weak self] in
            await self?.refresh(showSpinner: true)
            while !Task.isCancelled {
                guard let self, !Task.isCancelled else { return }
                await self.waitForNextTick()
                guard !Task.isCancelled else { return }
                if self.isRefreshing { continue }
                await self.refresh(showSpinner: false)
            }
        }
        // 版本检测：进主循环后单独跑一次，24 小时节流，不参与服务轮询
        Task { [weak self] in
            await self?.checkUpdateIfDue()
        }
    }

    /// 按当前前后台状态等待一个周期；被 `wake()` 打断时立即返回
    private func waitForNextTick() async {
        let interval = currentPollInterval
        if pollInterval != interval { pollInterval = interval }
        let sleeper = Task<Void, Never> {
            do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) } catch { }
        }
        wakeSignal = sleeper
        await sleeper.value
        if wakeSignal == sleeper { wakeSignal = nil }
    }

    /// 应用激活 / 失焦、窗口显隐变化时调用：结束当前等待，按新状态立即重排。
    /// 一分钟内连续弹窗、切窗口会连发多个通知，这里做去抖，避免刷新风暴。
    func wake() {
        if isRefreshing { return }
        if let last = lastRefresh, Date().timeIntervalSince(last) < 1 { return }
        wakeSignal?.cancel()
    }

    /// 轮询间隔规则：只有「应用在前台 + 主窗口可见」才用高频，其余降到低频。
    /// 抽成纯函数，方便 `--bench` 自检各分支。
    nonisolated static func pollInterval(active: Bool, hasVisibleWindow: Bool) -> TimeInterval {
        (active && hasVisibleWindow) ? foregroundInterval : backgroundInterval
    }

    private var currentPollInterval: TimeInterval {
        // 用 NSApplication.shared 而不是 NSApp：后者在没起过 App 的进程（--bench）里是 nil，
        // 隐式解包会直接 trap。
        let app = NSApplication.shared
        let hasVisibleWindow = app.windows.contains { window in
            window.canBecomeMain && !(window is NSPanel) && window.isVisible && !window.isMiniaturized
        }
        return Self.pollInterval(active: app.isActive, hasVisibleWindow: hasVisibleWindow)
    }

    private func observeActivity() {
        guard activityObservers.isEmpty else { return }
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.willCloseNotification,
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // 不能在内层并发闭包里直接读外层捕获的 weak self：weak 捕获在编译器眼里是
                // 可变存储，会报 "reference to captured var 'self' in concurrently-executing code"。
                // 先提升成强引用常量，Task 捕获的是 let，旧编译器（Swift 5.10）也放行。
                guard let model = self else { return }
                Task { @MainActor in model.wake() }
            }
            activityObservers.append(token)
        }
    }

    func refresh(showSpinner: Bool = true, runtimes: Bool? = nil) async {
        if isRefreshing { return }
        isRefreshing = true
        let stale = lastRuntimeProbe.map { Date().timeIntervalSince($0) > 90 } ?? true
        let needRuntimes = runtimes ?? stale
        var snapshot = await Self.collect(runtimes: needRuntimes)
        if needRuntimes {
            lastRuntimeProbe = Date()
        } else {
            snapshot.bun = bun
            snapshot.node = node
        }
        apply(snapshot)
        lastRefresh = Date()
        isRefreshing = false
    }

    /// 同步刷新（截图 / 调试 / CLI 用）
    func refreshSync(runtimes: Bool = true) {
        apply(Self.collectSync(runtimes: runtimes))
        lastRefresh = Date()
        if runtimes { lastRuntimeProbe = Date() }
    }

    private func apply(_ snap: SystemSnapshot) {
        brewVersionText = snap.brewVersion

        var entries: [String: BrewServiceEntry] = [:]
        for entry in snap.services { entries[entry.name] = entry }

        var merged: [ServiceItem] = []
        for spec in ServiceSpec.catalog {
            let entry = entries.removeValue(forKey: spec.id)
            merged.append(buildItem(spec: spec, entry: entry, snap: snap))
        }
        for name in entries.keys.sorted() {
            guard let entry = entries[name] else { continue }
            merged.append(buildItem(spec: .fallback(id: name), entry: entry, snap: snap))
        }

        // 保留进行中的动作标记
        for index in merged.indices {
            if let old = items.first(where: { $0.id == merged[index].id }), old.busy {
                merged[index].busy = old.busy
                merged[index].busyText = old.busyText
            }
        }

        items = merged
        bun = snap.bun
        node = snap.node
    }

    private func buildItem(spec: ServiceSpec, entry: BrewServiceEntry?, snap: SystemSnapshot) -> ServiceItem {
        var item = ServiceItem(spec: spec)
        item.version = snap.versions[spec.id] ?? spec.bundleVersion()

        switch spec.kind {
        case .brew:
            item.installed = item.version != nil || entry != nil || Paths.isDirectory(spec.cellarPath)
        case .managed:
            item.installed = spec.binaryPath() != nil
        case .external:
            item.installed = (spec.daemonPlist.map { Paths.exists($0) } ?? false) || spec.binaryPath() != nil
        }

        if let entry {
            item.status = entry.status
            item.user = entry.user
            item.plistPath = entry.file
            item.exitCode = entry.exitCode
        } else if spec.kind != .brew {
            item.plistPath = spec.effectivePlist
            item.status = item.installed ? .stopped : .none
        } else {
            item.status = item.installed ? .stopped : .none
        }

        switch spec.kind {
        case .brew:
            item.loginItem = Paths.loginItemExists(for: spec.id)
        case .managed:
            item.loginItem = Paths.exists(spec.managedPlistPath)
        case .external:
            item.loginItem = spec.daemonPlist.map { Paths.exists($0) } ?? false
        }
        item.pid = snap.processPIDs[spec.id]
        // 非 brew 服务以进程存活作为运行状态
        if spec.kind != .brew {
            item.status = item.pid != nil ? .started : (item.installed ? .stopped : .none)
        }

        if let pid = item.pid, let owner = snap.portOwners.first(where: { $0.pid == pid }) {
            item.ports = owner.ports
        }

        let portOwner = spec.defaultPort.flatMap { port in
            snap.portOwners.first { $0.ports.contains(port) }
        }
        var ownerBelongs = false
        if let portOwner {
            if portOwner.pid == item.pid {
                ownerBelongs = true
            } else if spec.matches(command: portOwner.command) {
                ownerBelongs = true
            } else if spec.isJavaBased, portOwner.command.lowercased() == "java" {
                ownerBelongs = true
            }
        }

        if item.ports.isEmpty, item.isRunning, ownerBelongs, let port = spec.defaultPort {
            item.ports = [port]
        }
        if item.ports.count > 1 {
            let preferred = spec.defaultPort
            item.ports = item.ports.sorted { lhs, rhs in
                if lhs == preferred { return true }
                if rhs == preferred { return false }
                return lhs < rhs
            }
        }
        if item.pid == nil, item.isRunning, ownerBelongs {
            item.pid = portOwner?.pid
        }
        if let port = spec.defaultPort, let owner = portOwner, !ownerBelongs {
            item.portConflict = L.t("端口 %d 被 %@（PID %d）占用", port, owner.command, owner.pid)
        }
        return item
    }

    // MARK: - 查询

    func item(_ id: String) -> ServiceItem? {
        items.first { $0.id == id }
    }

    func items(in category: ServiceCategory) -> [ServiceItem] {
        items.filter { $0.spec.category == category }
    }

    func installedItems() -> [ServiceItem] {
        items.filter { $0.installed }
    }

    func uninstalledItems() -> [ServiceItem] {
        items.filter { !$0.installed }
    }

    func count(category: ServiceCategory) -> (total: Int, running: Int) {
        let list = items(in: category).filter { $0.installed }
        return (list.count, list.filter { $0.isRunning }.count)
    }

    var runningCount: Int { items.filter { $0.isRunning }.count }

    var problemCount: Int { items.filter { $0.status.isProblem }.count }

    /// 概览 / 分类页展示的卡片集合
    func visibleItems(scope: ServiceCategory?) -> [ServiceItem] {
        var list = items.filter { $0.installed }
        if let scope {
            list = list.filter { $0.spec.category == scope }
        }
        if showOnlyRunning {
            list = list.filter { $0.isRunning }
        }
        if !searchText.isEmpty {
            let keyword = searchText.lowercased()
            list = list.filter {
                $0.title.lowercased().contains(keyword)
                    || $0.id.lowercased().contains(keyword)
                    || $0.spec.summary.contains(searchText)
            }
        }
        return list
    }

    // MARK: - 提示

    func show(_ toast: ToastMessage) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { self.toast = toast }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) { self?.toast = nil }
            }
        }
    }

    func copyToPasteboard(_ text: String, label: String? = nil) {
        let title = L.t(label ?? "内容")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show(.success(L.t("已复制%@：%@", title, text)))
    }

    func reveal(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            show(.error(L.t("路径不存在：%@", path)))
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            show(.error(L.t("路径不存在：%@", path)))
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openInTerminal(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            show(.error(L.t("无法打开终端：%@", String(describing: error))))
        }
    }
}
