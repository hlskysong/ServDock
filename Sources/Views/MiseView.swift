import SwiftUI

// MARK: - mise 开发环境管理

struct MiseView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var showAllTools = false

    private var snap: MiseSnapshot { model.mise }

    private let presets = ["node", "python", "go", "rust", "java", "bun", "deno", "ruby", "php", "terraform", "kubectl", "uv"]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let busy = model.miseBusy {
                        busyBanner(busy)
                    }
                    if !snap.installed {
                        installPrompt
                    } else {
                        summaryCard
                        if !snap.activated {
                            activationCard
                        }
                        toolsSection
                        installSection
                    }
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 30)
            }
        }
        .task {
            if snap.version.isEmpty {
                await model.loadMise()
            }
        }
        .sheet(isPresented: Binding(
            get: { model.miseVersionSheet != nil },
            set: { if !$0 { model.miseVersionSheet = nil } }
        )) {
            MiseVersionSheet(tool: model.miseVersionSheet ?? "")
                .environmentObject(model)
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            IconBadge(symbol: "wrench.and.screwdriver.fill", tint: Theme.purple, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("mise")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    if !snap.version.isEmpty {
                        Text(snap.version)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.cardSoft))
                    }
                    if snap.updateAvailable {
                        TagChip(text: L.t("有新版本"), tint: Theme.amber)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if snap.updateAvailable {
                    PillButton(title: L.t("升级 mise"), systemImage: "arrow.up.circle", tint: Theme.purple, compact: true, loading: model.miseBusy != nil) {
                        Task { await model.selfUpdateMise() }
                    }
                }
                PillButton(title: L.t("刷新"), systemImage: "arrow.clockwise", compact: true, loading: model.miseLoading) {
                    Task { await model.loadMise() }
                }
            }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        if !snap.installed { return L.t("未检测到 mise") }
        let count = snap.toolNames.count
        return L.t("统一的开发环境 / 版本管理器 · 已管理 %d 个工具", count)
    }

    private func busyBanner(_ text: String) -> some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accent.opacity(0.08)))
    }

    // MARK: 未安装

    private var installPrompt: some View {
        VStack(spacing: 12) {
            EmptyStateView(
                symbol: "wrench.and.screwdriver",
                title: L.t("未检测到 mise"),
                message: L.t("mise 用一份配置管理 node / python / go / rust 等几百种工具的版本。可以通过 Homebrew 安装。"),
                actionTitle: model.miseBusy == nil ? L.t("安装 mise") : L.t("安装中…"),
                action: { Task { await model.installMise() } }
            )
            .cardSurface()
        }
    }

    // MARK: 概览

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
                InfoTile(label: L.t("版本"), value: snap.version.isEmpty ? "—" : snap.version, mono: true)
                InfoTile(label: L.t("已管理工具"), value: "\(snap.toolNames.count)")
                InfoTile(label: L.t("shell 激活"),
                         value: snap.activated
                            ? L.t("已激活 %@", snap.activatedShells.joined(separator: " / "))
                            : L.t("未激活"),
                         tint: snap.activated ? Theme.green : Theme.amber)
                InfoTile(label: L.t("登录 shell"),
                         value: snap.loginShell.isEmpty ? "—" : snap.loginShell,
                         mono: true)
            }

            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
                Text(shortPath(snap.dataDir))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                IconButton(systemImage: "folder", size: 18, help: L.t("在 Finder 中显示")) {
                    model.reveal(snap.dataDir)
                }
                if let config = snap.configFile {
                    IconButton(systemImage: "doc.text", size: 18, help: L.t("打开全局配置")) {
                        model.open(config)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 激活引导

    /// `mise activate` 只打印脚本，必须 source；这里给能直接照抄的命令并支持一键写入。
    private var activationCard: some View {
        let shell = snap.loginShell.isEmpty ? "zsh" : snap.loginShell
        let snippet = MiseProbe.activationSnippet(shell)
        let target = MiseProbe.activationTarget(shell).map(shortPath) ?? "—"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.amber)
                Text(L.t("mise 还没有在你的 shell 里生效"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 6)
                TagChip(text: shell, tint: Theme.purple)
            }

            Text(L.t("直接执行 mise activate 只会把脚本打印到屏幕上，必须交给 shell 执行。你的登录 shell 是 %@，正确写法：", shell))
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("$ " + snippet)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.cardSoft))
                IconButton(systemImage: "doc.on.doc", size: 20, help: L.t("复制命令")) {
                    model.copyToPasteboard(snippet, label: "命令")
                }
            }

            HStack(spacing: 8) {
                PillButton(title: L.t("写入 %@ 配置", shell),
                           systemImage: "square.and.pencil",
                           tint: Theme.purple,
                           kind: .primary,
                           compact: true,
                           loading: model.miseActivating != nil) {
                    Task { await model.writeMiseActivation(shell: shell) }
                }
                .fixedSize()
                Text(target)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            Text(L.t("写入后新开一个终端，或执行 source %@", target))
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if !snap.shimsDirExists {
                Text(L.t("新版 mise 通过 activate 直接注入 PATH，不再依赖 shims 目录，所以这里是空的不算问题。"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.amber.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.amber.opacity(0.28), lineWidth: 1))
    }

    // MARK: 已装工具

    private var toolsSection: some View {
        let all = snap.tools
        let visible = showAllTools ? all : Array(all.prefix(10))
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: L.t("已安装工具"), trailing: L.t("%d 个", all.count))
                if all.count > 10 {
                    Button(showAllTools ? L.t("收起") : L.t("展开全部")) {
                        withAnimation(.easeInOut(duration: 0.16)) { showAllTools.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
            }

            if all.isEmpty {
                EmptyStateView(
                    symbol: "wrench.and.screwdriver",
                    title: L.t("还没有安装任何工具"),
                    message: L.t("在下方搜索框里找工具，或者直接点常用工具。")
                )
                .frame(maxWidth: .infinity)
                .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, tool in
                        toolRow(tool)
                        if index < visible.count - 1 {
                            Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1).padding(.leading, 12)
                        }
                    }
                }
                .cardSurface()
            }
        }
    }

    private func toolRow(_ tool: MiseTool) -> some View {
        let busy = model.miseBusy?.contains(tool.name) == true
        return HStack(spacing: 10) {
            Image(systemName: tool.active ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 11))
                .foregroundStyle(tool.active ? Theme.green : Theme.textTertiary)
                .frame(width: 14)
            Text(tool.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            Text(tool.version)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.purple)
                .frame(width: 100, alignment: .leading)
            if !tool.installed {
                TagChip(text: L.t("未下载"), tint: Theme.amber)
            }
            if tool.active {
                TagChip(text: L.t("当前"), tint: Theme.green)
            }
            Spacer(minLength: 4)
            Text(shortPath(tool.installPath))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 260, alignment: .trailing)
            PillButton(title: L.t("升级"), systemImage: "arrow.up.circle", compact: true, loading: busy, enabled: model.miseBusy == nil) {
                Task { await model.upgradeMiseTool(tool) }
            }
            IconButton(systemImage: "trash", size: 20, help: L.t("卸载")) {
                Task { await model.uninstallMiseTool(tool) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: 安装

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: L.t("安装工具"), trailing: nil)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    TextField(L.t("搜索 mise registry，例如 node / python"), text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit { runSearch() }
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 120, maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 1))

                PillButton(title: L.t("搜索"), systemImage: "magnifyingglass", tint: Theme.purple, kind: .primary, compact: true,
                           loading: model.miseSearching,
                           enabled: !query.trimmingCharacters(in: .whitespaces).isEmpty) {
                    runSearch()
                }
                .fixedSize()
            }

            if model.miseSearching {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(L.t("正在搜索…"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 10)
            } else if !model.miseSearchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(model.miseSearchResults.enumerated()), id: \.element.id) { index, entry in
                        registryRow(entry)
                        if index < model.miseSearchResults.count - 1 {
                            Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1).padding(.leading, 12)
                        }
                    }
                }
                .cardSurface()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("常用工具"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                    FlowLayout(spacing: 6) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                model.miseVersionSheet = preset
                            } label: {
                                Text(preset)
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.purple)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .background(Capsule().fill(Theme.purple.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
    }

    private func registryRow(_ entry: MiseRegistryEntry) -> some View {
        let installed = snap.toolNames.contains(entry.name)
        return HStack(spacing: 10) {
            IconBadge(symbol: "cube.fill", tint: Theme.purple, size: 24)
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    if installed {
                        TagChip(text: L.t("已安装"), tint: Theme.green)
                    }
                }
                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2)
                } else if !entry.backends.isEmpty {
                    Text(entry.backends)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            PillButton(title: installed ? L.t("再装一版") : L.t("安装"), systemImage: "arrow.down.circle",
                       tint: Theme.purple, kind: installed ? .secondary : .primary, compact: true,
                       enabled: model.miseBusy == nil) {
                model.miseVersionSheet = entry.name
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func runSearch() {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return }
        Task { await model.searchMise(keyword) }
    }

    private func shortPath(_ path: String) -> String {
        guard !path.isEmpty else { return "—" }
        return path.replacingOccurrences(of: Shell.home, with: "~")
    }
}

// MARK: - 版本选择

struct MiseVersionSheet: View {
    let tool: String
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [String] = []
    @State private var loading = true
    @State private var custom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconBadge(symbol: "cube.fill", tint: Theme.purple, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L.t("安装 %@", tool))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L.t("通过 mise use -g 安装并写入全局配置"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                TextField(L.t("版本号，留空为 latest"), text: $custom)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                PillButton(title: L.t("安装"), systemImage: "arrow.down.circle", tint: Theme.purple, kind: .primary, compact: true) {
                    let target = custom.trimmingCharacters(in: .whitespaces)
                    let toolSpec = target.isEmpty ? "\(tool)@latest" : "\(tool)@\(target)"
                    dismiss()
                    Task { await model.installMiseTool(toolSpec) }
                }
            }

            Rectangle().fill(Theme.border).frame(height: 1)

            if loading {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(L.t("正在获取版本列表…"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if versions.isEmpty {
                Text(L.t("没有取到版本列表，可以直接输入版本号安装。"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(versions.prefix(60), id: \.self) { version in
                            Button {
                                dismiss()
                                Task { await model.installMiseTool("\(tool)@\(version)") }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(version)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.purple)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Rectangle().fill(Theme.border.opacity(0.4)).frame(height: 1)
                        }
                    }
                }
                .frame(height: 240)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardSoft))
            }

            HStack {
                Spacer()
                PillButton(title: L.t("关闭"), compact: true) { dismiss() }
            }
        }
        .padding(18)
        .frame(width: 400)
        .background(Theme.page)
        .task {
            let list = await Task.detached { MiseProbe.remoteVersions(tool) }.value
            versions = list
            loading = false
        }
    }
}
