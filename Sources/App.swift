import AppKit
import SwiftUI

// MARK: - 入口（支持 --snapshot 离屏渲染）

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments

        // 改名遗留：老数据目录 / 日志目录合并到新目录（幂等，不覆盖）
        Brand.migrateLegacyDataIfNeeded()

        if let index = args.firstIndex(of: "--lang"), index + 1 < args.count {
            if let lang = Lang(rawValue: args[index + 1]) {
                L10n.setLanguage(lang)
            }
        }

        // 子命令式 CLI（给脚本 / AI 用）：ServDock list --json
        if args.count > 1, !args[1].hasPrefix("--") {
            MainActor.assumeIsolated { CLIRunner.run(Array(args.dropFirst())) }
            return
        }

        if args.contains("--probe") {
            ProbeRunner.run()
            return
        }

        if args.contains("--bench") {
            BenchRunner.run()
            return
        }

        // 把 mise activate 写进 shell 配置，和界面「写入配置」按钮走同一条代码路径
        if let index = args.firstIndex(of: "--mise-activate") {
            let shell = index + 1 < args.count && !args[index + 1].hasPrefix("--")
                ? args[index + 1] : MiseProbe.loginShell()
            let result = MiseProbe.writeActivation(shell)
            print(result.ok ? result.trimmedOut : result.errorText)
            exit(result.ok ? 0 : 1)
        }

        if let index = args.firstIndex(of: "--action"), index + 2 < args.count {
            let verb = ServiceVerb(rawValue: args[index + 1]) ?? .start
            let id = args[index + 2]
            if let outIndex = args.firstIndex(of: "--out"), outIndex + 1 < args.count {
                ActionRunner.outputPath = args[outIndex + 1]
            }
            Task { @MainActor in
                await ActionRunner.run(verb: verb, id: id)
                exit(0)
            }
            RunLoop.main.run()
            return
        }

        if let index = args.firstIndex(of: "--snapshot") {
            let path = index + 1 < args.count ? args[index + 1] : "/tmp/servdock.png"
            var select: String?
            if let selectIndex = args.firstIndex(of: "--select"), selectIndex + 1 < args.count {
                select = args[selectIndex + 1]
            }
            SnapshotRunner.render(to: path, select: select, dark: args.contains("--dark"), redact: args.contains("--redact"))
            return
        }

        ServDockApp.main()
    }
}

struct ServDockApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(L.t("启服"), id: "main") {
            RootView()
                .environmentObject(model)
                .id(model.lang)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 790)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(L.t("刷新状态")) {
                    Task {
                        await model.refresh(runtimes: true)
                        if model.selection == .timers { await model.loadTimers() }
                        if model.selection == .easytier { await model.loadEasyTier() }
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button(L.t("总览")) { model.selection = .overview }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Bun") { model.selection = .bun }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Node.js") { model.selection = .node }
                    .keyboardShortcut("3", modifiers: .command)
                Button(L.t("定时任务")) { model.selection = .timers }
                    .keyboardShortcut("4", modifiers: .command)
                Button(L.t("Homebrew 包")) { model.selection = .packages }
                    .keyboardShortcut("5", modifiers: .command)
                Button("mise") { model.selection = .mise }
                    .keyboardShortcut("6", modifiers: .command)
                Button("EasyTier") { model.selection = .easytier }
                    .keyboardShortcut("7", modifiers: .command)
                Button(L.t("容器")) { model.selection = .docker }
                    .keyboardShortcut("8", modifiers: .command)

                Divider()

                Button(L.t("切换到英文")) {
                    model.setLanguage(.en)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                Button(L.t("切换到中文")) {
                    model.setLanguage(.zh)
                }
            }
        }

        MenuBarExtra {
            MenuPanel()
                .environmentObject(model)
        } label: {
            Image(systemName: "shippingbox.fill")
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - 菜单栏面板

struct MenuPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var installed: [ServiceItem] {
        model.items.filter { $0.installed }
    }

    var body: some View {
        Text(L.t("%d 个服务运行中 · %d 个已安装", model.runningCount, installed.count))

        Divider()

        ForEach(installed) { item in
            Menu("\(item.title)  ·  \(item.status.title)") {
                Button(L.t("启动（含开机自启）")) { model.perform(.start, on: item.id) }
                    .disabled(item.isRunning)
                Button(L.t("仅本次启动")) { model.perform(.run, on: item.id) }
                    .disabled(item.isRunning)
                Button(L.t("停止")) { model.perform(.stop, on: item.id) }
                    .disabled(!item.isRunning)
                Button(L.t("重启")) { model.perform(.restart, on: item.id) }
                    .disabled(!item.isRunning)
            }
        }

        Divider()

        Button(L.t("刷新")) {
            Task {
                await model.refresh(runtimes: true)
                if model.selection == .timers { await model.loadTimers() }
            }
        }

        Button(L.t("打开主窗口")) { openMainWindow() }

        Divider()

        Button(L.t("退出启服")) {
            NSApp.terminate(nil)
        }
    }

    /// SwiftUI 的 WindowGroup 窗口是懒创建、关掉即销毁的：只遍历 NSApp.windows
    /// 在「窗口已被关掉」时必然是空操作（菜单里点「打开主窗口」没反应就是这个原因）。
    /// 所以先让 SwiftUI 用 openWindow 重建 / 前置窗口，再到下一个 runloop 把它拉到前台。
    private func openMainWindow() {
        NSApp.unhide(nil)
        openWindow(id: "main")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let target = NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }
            if let window = target {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - 离屏截图（自检 / 预览用）

enum SnapshotRunner {
    @MainActor
    static func render(to path: String, select: String?, dark: Bool, redact: Bool = false) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        app.appearance = appearance

        let model = AppModel(autoStart: false)
        model.refreshSync()
        model.lang = L10n.current

        let content: AnyView
        var size = CGSize(width: 1240, height: 800)

        switch select {
        case "detail", "logs", "config":
            let installed = model.items.first { $0.installed }
            if let installed {
                let initialTab: ServiceDetailView.Tab = select == "logs" ? .logs : (select == "config" ? .config : .overview)
                content = AnyView(
                    ServiceDetailView(itemID: installed.id, initialTab: initialTab)
                        .environmentObject(model)
                )
                size = CGSize(width: 720, height: 620)
            } else {
                content = AnyView(RootView().environmentObject(model))
            }
        case "bun":
            model.selection = .bun
            content = AnyView(RootView().environmentObject(model))
        case "node":
            model.selection = .node
            content = AnyView(RootView().environmentObject(model))
        case "timers", "cron":
            var snapshot = TimerProbe.scan()
            // 截图环境读不到 crontab（沙箱限制），按"没有任务"展示，避免文档里出现误导性报错
            if !snapshot.cronReadable {
                snapshot.cronReadable = true
                snapshot.cronError = nil
            }
            model.timers = snapshot
            model.snapshotMode = true
            if select == "cron" { model.timerScopeFilter = .cron }
            model.selection = .timers
            content = AnyView(RootView().environmentObject(model))
        case "category":
            model.selection = .category(.database)
            content = AnyView(RootView().environmentObject(model))
        case "storage":
            model.selection = .category(.storage)
            content = AnyView(RootView().environmentObject(model))
        case "easytier":
            let snapshot = EasyTierProbe.scan()
            model.easyTier = redact ? snapshot.redacted() : snapshot
            model.selection = .easytier
            content = AnyView(RootView().environmentObject(model))
        case "docker":
            model.docker = DockerProbe.scan()
            model.selection = .docker
            content = AnyView(RootView().environmentObject(model))
        case "docker-images":
            model.docker = DockerProbe.scan()
            model.dockerTab = .images
            model.selection = .docker
            content = AnyView(RootView().environmentObject(model))
        case "packages":
            model.brewInstalled = BrewCatalog.installedFormulae() + BrewCatalog.installedCasks()
            model.brewResults = BrewCatalog.search("redis", kind: "formula", limit: 16)
            model.brewLastQuery = "redis"
            model.selection = .packages
            content = AnyView(RootView().environmentObject(model))
        case "packages-installed":
            model.brewInstalled = BrewCatalog.installedFormulae() + BrewCatalog.installedCasks()
            model.brewTab = .installed
            model.selection = .packages
            content = AnyView(RootView().environmentObject(model))
        case "mise":
            model.mise = MiseProbe.scan()
            model.selection = .mise
            content = AnyView(RootView().environmentObject(model))
        case "settings":
            model.easyTier = EasyTierProbe.scan()
            model.mise = MiseProbe.scan()
            model.selection = .settings
            content = AnyView(RootView().environmentObject(model))        default:
            model.selection = .overview
            content = AnyView(RootView().environmentObject(model))
        }

        let root = content
            .frame(width: size.width, height: size.height)
            .background(Theme.page)
            .id(model.lang)

        // 用离屏 NSHostingView 渲染，ScrollView / TextField 才能正常出图
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -12000, y: -12000))
        window.orderFrontRegardless()

        for _ in 0..<12 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.06))
        }
        hosting.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            FileHandle.standardError.write(Data("snapshot: 无法创建位图\n".utf8))
            exit(1)
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("snapshot: PNG 编码失败\n".utf8))
            exit(1)
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("snapshot -> \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
        } catch {
            FileHandle.standardError.write(Data("snapshot: 写入失败 \(error)\n".utf8))
            exit(1)
        }
    }
}
