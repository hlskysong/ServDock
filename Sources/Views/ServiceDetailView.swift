import SwiftUI

struct ServiceDetailView: View {
    let itemID: String

    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var tab: Tab = .overview
    @State private var logPath: String?
    @State private var logText = ""
    @State private var autoRefresh = true
    @State private var configPath: String?
    @State private var configText = ""

    private let logTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    enum Tab: String, CaseIterable {
        case overview
        case logs
        case config

        var title: String {
            switch self {
            case .overview: return L.t("概览")
            case .logs: return L.t("日志")
            case .config: return L.t("配置")
            }
        }
    }

    init(itemID: String, initialTab: Tab = .overview) {
        self.itemID = itemID
        _tab = State(initialValue: initialTab)
    }

    private var item: ServiceItem? { model.item(itemID) }

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                Text(L.t("服务信息已失效"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 640, height: 420)
            }
        }
        .background(Theme.page)
    }

    private func content(_ item: ServiceItem) -> some View {
        VStack(spacing: 0) {
            header(item)
            tabBar
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    switch tab {
                    case .overview: overviewTab(item)
                    case .logs: logsTab(item)
                    case .config: configTab(item)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .frame(width: 720, height: 420)
            footer(item)
        }
        .frame(width: 720)
        .background(Theme.page)
        .onAppear {
            if tab == .logs { loadLog(item) }
        }
        .onChange(of: tab) { _, newValue in
            if newValue == .logs { loadLog(item) }
            if newValue == .config { loadConfig(item) }
        }
        .onReceive(logTimer) { _ in
            if tab == .logs, autoRefresh { loadLog(item) }
        }
    }

    // MARK: 头部

    private func header(_ item: ServiceItem) -> some View {
        HStack(spacing: 10) {
            IconBadge(symbol: ServiceGlyph.symbol(for: item.id), tint: item.spec.category.tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(item.versionText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(item.spec.summary + " · " + item.spec.category.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            StatusPill(status: item.status)
            IconButton(systemImage: "xmark", size: 24, help: "关闭") { dismiss() }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(Tab.allCases, id: \.self) { value in
                Button {
                    tab = value
                } label: {
                    Text(value.title)
                        .font(.system(size: 11.5, weight: tab == value ? .semibold : .regular))
                        .foregroundStyle(tab == value ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4.5)
                        .background(
                            Capsule().fill(tab == value ? Theme.card : Color.clear)
                        )
                        .overlay(
                            Capsule().strokeBorder(tab == value ? Theme.border : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardSoft))
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    // MARK: 概览

    private func overviewTab(_ item: ServiceItem) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                KeyValueRow(
                    label: item.spec.kind == .brew ? "Formula" : "标识",
                    value: item.id, mono: true, copyable: true
                ) {
                    model.copyToPasteboard(item.id, label: "标识")
                }
                dividerRow
                KeyValueRow(label: "托管方式", value: item.spec.kind.title)
                dividerRow
                KeyValueRow(label: "版本", value: item.versionText, mono: true)
                dividerRow
                KeyValueRow(label: "状态", value: item.status.title)
                if let pid = item.pid {
                    dividerRow
                    KeyValueRow(label: "PID", value: "\(pid)", mono: true)
                }
                dividerRow
                KeyValueRow(label: "端口", value: item.portText, mono: true)
                if let address = item.address {
                    dividerRow
                    KeyValueRow(label: "访问地址", value: address, mono: true, copyable: true) {
                        model.copyToPasteboard(address, label: "地址")
                    }
                }
                if let console = item.spec.consolePort {
                    dividerRow
                    KeyValueRow(label: "控制台", value: "http://127.0.0.1:\(console)", mono: true, copyable: true) {
                        model.copyToPasteboard("http://127.0.0.1:\(console)", label: "控制台地址")
                    }
                }
                dividerRow
                KeyValueRow(label: "开机自启", value: item.loginItem ? L.t("已启用（登录项）") : L.t("未启用"))
                if let plist = item.plistPath {
                    dividerRow
                    KeyValueRow(label: "launchd", value: shortPath(plist), mono: true, copyable: true) {
                        model.copyToPasteboard(plist, label: "plist 路径")
                    }
                }
                if let exit = item.exitCode, exit != 0 {
                    dividerRow
                    KeyValueRow(label: "退出码", value: "\(exit)", mono: true)
                }
                if let note = item.spec.note {
                    dividerRow
                    KeyValueRow(label: "说明", value: L.t(note))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .cardSurface()

            if let configs = configPaths(item), !configs.isEmpty {
                pathSection(title: "配置文件", paths: configs, symbol: "doc.text")
            }
            if let data = dataPaths(item), !data.isEmpty {
                pathSection(title: "数据 / 日志目录", paths: data, symbol: "folder")
            }
            if let error = item.lastError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 10.5))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Theme.red)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.red.opacity(0.08)))
            }
        }
    }

    private var dividerRow: some View {
        Rectangle().fill(Theme.border.opacity(0.55)).frame(height: 1)
    }

    private func pathSection(title: String, paths: [String], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t(title))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            ForEach(paths, id: \.self) { path in
                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                    Text(shortPath(path))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    IconButton(systemImage: "folder", size: 18, help: "在 Finder 中显示") {
                        model.reveal(path)
                    }
                    IconButton(systemImage: "arrow.up.forward.app", size: 18, help: "打开") {
                        model.open(path)
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 日志

    private func logsTab(_ item: ServiceItem) -> some View {
        let candidates = LogLocator.candidates(for: item)
        let current = candidates.first { $0.path == logPath } ?? candidates.first

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    if candidates.isEmpty {
                        Text(L.t("没有找到日志文件"))
                    }
                    ForEach(candidates) { candidate in
                        Button {
                            logPath = candidate.path
                            loadLog(item)
                        } label: {
                            Text("\(candidate.name)  ·  \(candidate.sizeText)")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9.5))
                        Text(current?.name ?? L.t("无日志文件"))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.card))
                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                if let current {
                    Text(shortPath(current.path))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                PillButton(
                    title: "自动刷新",
                    systemImage: autoRefresh ? "checkmark.circle.fill" : "circle",
                    tint: Theme.green,
                    kind: autoRefresh ? .ghost : .secondary,
                    compact: true
                ) {
                    autoRefresh.toggle()
                }
                PillButton(title: "刷新", systemImage: "arrow.clockwise", compact: true) {
                    loadLog(item)
                }
                if let current {
                    IconButton(systemImage: "folder", size: 20, help: "在 Finder 中显示") {
                        model.reveal(current.path)
                    }
                }
            }

            if candidates.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.textTertiary)
                    Text(L.t("没有找到这个服务的日志文件"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                    Text(L.t("Homebrew 服务只在有输出时才会写日志"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(logText.isEmpty ? L.t("（日志为空）") : logText)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear.frame(height: 1).id("logBottom")
                        }
                        .padding(10)
                    }
                    .frame(height: 330)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 1))
                    .onChange(of: logText) {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: 配置

    private func configTab(_ item: ServiceItem) -> some View {
        let paths = configPaths(item) ?? []
        return VStack(alignment: .leading, spacing: 8) {
            if paths.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.textTertiary)
                    Text(L.t("没有找到默认配置文件"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                    Text(L.t("该服务可能不需要配置文件，或用命令行参数启动"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                HStack(spacing: 6) {
                    ForEach(paths, id: \.self) { path in
                        Button {
                            configPath = path
                            loadConfig(item)
                        } label: {
                            Text((path as NSString).lastPathComponent)
                                .font(.system(size: 10.5, weight: (configPath ?? paths.first) == path ? .semibold : .regular))
                                .foregroundStyle((configPath ?? paths.first) == path ? Theme.textPrimary : Theme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(Capsule().fill((configPath ?? paths.first) == path ? Theme.card : Color.clear))
                                .overlay(Capsule().strokeBorder(Theme.border.opacity(0.8), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    if let path = configPath ?? paths.first {
                        IconButton(systemImage: "arrow.up.forward.app", size: 20, help: "用默认应用打开") {
                            model.open(path)
                        }
                        IconButton(systemImage: "folder", size: 20, help: "在 Finder 中显示") {
                            model.reveal(path)
                        }
                    }
                }

                ScrollView(.vertical) {
                    Text(configText.isEmpty ? L.t("（空文件）") : configText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 330)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.cardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 1))
            }
        }
        .onAppear { loadConfig(item) }
    }

    // MARK: 底部操作

    private func footer(_ item: ServiceItem) -> some View {
        HStack(spacing: 6) {
            if item.isRunning {
                PillButton(title: "停止", systemImage: "stop.fill", kind: .danger) {
                    model.perform(.stop, on: item.id)
                }
                PillButton(title: "重启", systemImage: "arrow.triangle.2.circlepath") {
                    model.perform(.restart, on: item.id)
                }
            } else {
                PillButton(title: "启动", systemImage: "play.fill", tint: Theme.green, kind: .primary) {
                    model.perform(.start, on: item.id)
                }
                if item.supportsRun {
                    PillButton(title: "仅本次启动", systemImage: "bolt.fill") {
                        model.perform(.run, on: item.id)
                    }
                }
            }
            Spacer()
            PillButton(title: "终端", systemImage: "terminal", compact: true) {
                model.openInTerminal(item.statusCommand)
            }
            if let address = item.address {
                PillButton(title: "复制地址", systemImage: "doc.on.doc", compact: true) {
                    model.copyToPasteboard(address, label: "地址")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(Theme.page)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    // MARK: 数据加载

    private func loadLog(_ item: ServiceItem) {
        let candidates = LogLocator.candidates(for: item)
        guard !candidates.isEmpty else {
            logText = ""
            return
        }
        let target = candidates.first { $0.path == logPath } ?? candidates[0]
        if logPath != target.path { logPath = target.path }
        logText = LogLocator.tail(target.path, maxBytes: 60_000)
    }

    private func loadConfig(_ item: ServiceItem) {
        let paths = configPaths(item) ?? []
        guard let first = paths.first else {
            configText = ""
            return
        }
        let target = configPath ?? first
        if configPath == nil { configPath = first }
        configText = LogLocator.readText(target, maxBytes: 60_000)
    }

    private func configPaths(_ item: ServiceItem) -> [String]? {
        var result = item.spec.configPaths()
        if let plist = item.plistPath {
            result.append(plist)
        }
        return result
    }

    private func dataPaths(_ item: ServiceItem) -> [String]? {
        item.spec.dataPaths()
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(of: Shell.home, with: "~")
    }
}
