import AppKit
import Foundation

/// 命令行自检：`ServDock --bench`
///
/// 用来量化「轮询一轮到底开多少子进程、花多少时间」，并验证两条节流策略确实生效：
/// 1. `brew --version` / `brew list --versions` 的 60 秒缓存（冷 / 热采集对比子进程数与耗时）
/// 2. 前后台自适应轮询间隔（纯函数四分支断言）
enum BenchRunner {
    static func run() {
        print("== 采集一轮的代价（brew 缓存前 / 后）==")
        let cold = measureCycle()
        let warm = measureCycle()
        let warm2 = measureCycle()
        print(String(format: "冷启动采集 : 子进程 %2d 次   墙钟 %5.0f ms（brew 两条命令真实执行）", cold.spawns, cold.interval))
        print(String(format: "缓存命中   : 子进程 %2d 次   墙钟 %5.0f ms", warm.spawns, warm.interval))
        print(String(format: "缓存命中   : 子进程 %2d 次   墙钟 %5.0f ms", warm2.spawns, warm2.interval))
        if cold.spawns > warm.spawns {
            print("单轮减少   : \(cold.spawns - warm.spawns) 个子进程")
        }

        print("")
        print("== 单项耗时 ==")
        BrewCache.shared.invalidate()
        print(String(format: "brew --version        (冷): %6.0f ms", measure { _ = SystemProbe.brewHomebrewVersion(force: true) }))
        print(String(format: "brew --version        (热): %6.0f ms", measure { _ = SystemProbe.brewHomebrewVersion() }))
        print(String(format: "brew list --versions  (冷): %6.0f ms", measure { _ = SystemProbe.brewVersions(force: true) }))
        print(String(format: "brew list --versions  (热): %6.0f ms", measure { _ = SystemProbe.brewVersions() }))

        print("")
        print("== mise shell 激活检测 ==")
        let miseSnap = MiseProbe.scan()
        print("登录 shell   : \(miseSnap.loginShell.isEmpty ? "未知" : miseSnap.loginShell)")
        print("激活判定     : \(miseSnap.activated ? "已激活" : "未激活")（看 shell 启动文件，不看 doctor 的进程环境）")
        for item in miseSnap.activations {
            let state: String
            if let file = item.configuredFile {
                state = "已配置 -> " + MiseProbe.shorten(file)
            } else {
                state = item.exists ? "未配置" : "启动文件不存在"
            }
            print(String(format: "  %-6@: %@", item.shell as NSString, state))
        }
        print("激活命令     : \(MiseProbe.activationSnippet(miseSnap.loginShell))")
        if let target = MiseProbe.activationTarget(miseSnap.loginShell) {
            print("写入目标     : \(MiseProbe.shorten(target))")
        }
        print("shims 目录   : " + (miseSnap.shimsDirExists ? "存在" : "不存在（新版 mise 靠 activate 注入 PATH，不是问题）"))

        print("")
        print("== 轮询间隔规则 ==")
        let cases: [(String, Bool, Bool)] = [
            ("前台 + 窗口可见", true, true),
            ("前台 + 窗口已关", true, false),
            ("后台 + 窗口可见", false, true),
            ("后台 + 窗口已关", false, false),
        ]
        for (name, active, visible) in cases {
            let value = AppModel.pollInterval(active: active, hasVisibleWindow: visible)
            print(String(format: "%-16@ -> %2.0f 秒", name as NSString, value))
        }
        print("")
        print("频率常量     : 前台 \(Int(AppModel.foregroundInterval)) 秒 / 后台 \(Int(AppModel.backgroundInterval)) 秒")
        print("缓存有效期   : \(Int(BrewCache.ttl)) 秒")

        print("")
        print("== 轮询唤醒链路 ==")
        Task { @MainActor in
            await checkWakeChain()
            exit(0)
        }
        RunLoop.main.run()
    }

    /// 验证「等满一个周期」与「收到激活通知立刻醒来」两条路径
    @MainActor
    private static func checkWakeChain() async {
        let model = AppModel(autoStart: false)
        model.start()

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard let first = model.lastRefresh else {
            print("启动后 2 秒内没有完成首次刷新（后台任务未调度）")
            return
        }
        print(String(format: "启动首刷     : %@（当前间隔 %2.0f 秒）", stamp(first), model.pollInterval))

        try? await Task.sleep(nanoseconds: 2_500_000_000)
        let idle = model.lastRefresh ?? first
        print("静置 2.5 秒  : " + (idle == first ? "无新刷新，正在等下一个周期（符合预期）" : "又刷新了一次"))

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let woke = model.lastRefresh ?? idle
        print("发激活通知后 : " + (woke > idle ? "立刻刷新，唤醒链路通" : "没有刷新，唤醒链路可能断了"))
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private static func measureCycle() -> (spawns: Int, interval: Double) {
        Shell.resetSpawnCount()
        let start = Date()
        _ = AppModel.collectSync(runtimes: false)
        let interval = Date().timeIntervalSince(start) * 1000
        return (Shell.spawnCount(), interval)
    }

    private static func measure(_ body: () -> Void) -> Double {
        let start = Date()
        body()
        return Date().timeIntervalSince(start) * 1000
    }
}
