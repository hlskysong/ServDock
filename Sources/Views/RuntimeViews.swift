import SwiftUI

// MARK: - 运行时时页面头部

struct RuntimeHeader: View {
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
    var trailing: AnyView

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            IconBadge(symbol: symbol, tint: tint, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t(title))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L.t(subtitle))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }
}

struct InfoTile: View {
    var label: String
    var value: String
    var mono = false
    var tint: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L.t(label))
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: mono ? .monospaced : .default))
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

struct ChipFlow: View {
    var values: [String]
    var tint: Color

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(tint.opacity(0.1)))
            }
        }
    }
}

/// 简单的流式布局
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 600
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Bun

struct BunView: View {
    @EnvironmentObject var model: AppModel

    private var info: BunInfo { model.bun }

    var body: some View {
        VStack(spacing: 0) {
            RuntimeHeader(
                title: "Bun",
                subtitle: info.installed ? "JavaScript 运行时 · 内置打包器与测试器" : "尚未安装 Bun",
                symbol: "hare.fill",
                tint: Theme.pink,
                trailing: AnyView(
                    HStack(spacing: 6) {
                        IconButton(systemImage: "arrow.clockwise", size: 26, help: "刷新") {
                            Task { await model.refresh(runtimes: true) }
                        }
                    }
                )
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if model.runtimeBusy != nil {
                        busyBanner(model.runtimeBusy ?? "")
                    }
                    if info.installed {
                        installedContent
                    } else {
                        installContent
                    }
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 30)
            }
        }
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

    private var installedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: "hare.fill", tint: Theme.pink, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Bun")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("v" + info.version)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.pink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.pink.opacity(0.12)))
                        if info.shellConfigured {
                            TagChip(text: "PATH 已检测", tint: Theme.green)
                        } else {
                            TagChip(text: "PATH 未检测到", tint: Theme.amber)
                        }
                    }
                    Text(L.t("全局 bin 目录：%@", shortPath((info.path as NSString).deletingLastPathComponent)))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                PillButton(title: "升级到最新", systemImage: "arrow.up.circle", tint: Theme.pink, kind: .primary) {
                    Task { await model.upgradeBun() }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
                InfoTile(label: "版本", value: "v" + info.version, mono: true)
                InfoTile(label: "全局缓存", value: info.cacheSize)
                InfoTile(label: "全局工具", value: L.t("%d 个", info.binTools.count))
                InfoTile(label: "PATH 检测", value: info.shellConfigured ? (info.shellConfigFile ?? "已检测") : "未检测到", tint: info.shellConfigured ? Theme.green : Theme.amber)
            }

            if !info.binTools.isEmpty {
                sectionCard(title: "全局可执行", subtitle: L.t("位于 %@", shortPath(info.path))) {
                    ChipFlow(values: info.binTools, tint: Theme.pink)
                }
            }

            if !info.globalPackages.isEmpty {
                sectionCard(title: "全局包", subtitle: "~/.bun/install/global") {
                    ChipFlow(values: info.globalPackages, tint: Theme.slate)
                }
            }

            if !info.shellConfigured {
                sectionCard(title: "PATH 提示", subtitle: nil) {
                    Text(L.t("把 export PATH=\"$HOME/.bun/bin:$PATH\" 加到 shell 配置文件里，终端才能直接用 bun 命令。"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var installContent: some View {
        VStack(spacing: 12) {
            EmptyStateView(
                symbol: "hare",
                title: "未检测到 Bun",
                message: "Bun 会安装到 ~/.bun/bin，需要网络从 bun.sh 下载。",
                actionTitle: model.runtimeBusy == nil ? "安装 Bun" : "安装中…",
                action: { Task { await model.installBun() } }
            )
            .cardSurface()
        }
    }

    private func sectionCard<Content: View>(title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.t(title))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(L.t(subtitle))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(of: Shell.home, with: "~")
    }
}

// MARK: - Node / fnm

struct NodeView: View {
    @EnvironmentObject var model: AppModel
    @State private var pendingUninstall: String?

    private var snapshot: NodeSnapshot { model.node }

    var body: some View {
        VStack(spacing: 0) {
            RuntimeHeader(
                title: "Node.js",
                subtitle: snapshot.fnmInstalled
                    ? L.t("fnm %@ · %d 个版本", snapshot.fnmVersion, snapshot.versions.count)
                    : "未检测到 fnm",
                symbol: "hexagon.fill",
                tint: Theme.green,
                trailing: AnyView(
                    HStack(spacing: 6) {
                        PillButton(title: "安装版本", systemImage: "plus", tint: Theme.green, kind: .primary, compact: true) {
                            model.nodeInstallSheet = true
                        }
                        IconButton(systemImage: "arrow.clockwise", size: 26, help: "刷新") {
                            Task { await model.refresh(runtimes: true) }
                        }
                    }
                )
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let busy = model.runtimeBusy {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text(busy)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accent.opacity(0.08)))
                    }

                    if !snapshot.fnmInstalled {
                        EmptyStateView(
                            symbol: "hexagon",
                            title: "未检测到 fnm",
                            message: "fnm 是快速的 Node 版本管理器，可通过 Homebrew 安装。",
                            actionTitle: model.runtimeBusy == nil ? "安装 fnm" : "安装中…",
                            action: { Task { await model.installFnm() } }
                        )
                        .cardSurface()
                    } else {
                        summaryRow
                        versionsCard
                        if !snapshot.shellConfigured {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 10))
                                Text(L.t("未在 shell 配置中找到 fnm env，终端可能无法自动切换版本"))
                                    .font(.system(size: 10.5))
                            }
                            .foregroundStyle(Theme.amber)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.amber.opacity(0.1)))
                        }
                    }
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 30)
            }
        }
        .alert(L.t("卸载 Node %@？", pendingUninstall ?? ""), isPresented: Binding(
            get: { pendingUninstall != nil },
            set: { if !$0 { pendingUninstall = nil } }
        )) {
            Button(L.t("取消"), role: .cancel) { pendingUninstall = nil }
            Button(L.t("卸载"), role: .destructive) {
                if let version = pendingUninstall {
                    Task { await model.uninstallNode(version) }
                }
                pendingUninstall = nil
            }
        } message: {
            Text(L.t("会删除该版本的 node 可执行文件，该版本下安装的全局包也会一起删除。"))
        }
    }

    private var summaryRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
            InfoTile(label: "fnm 版本", value: snapshot.fnmVersion.isEmpty ? "—" : snapshot.fnmVersion, mono: true)
            InfoTile(label: "默认版本", value: snapshot.defaultVersion ?? "未设置", mono: true, tint: Theme.green)
            InfoTile(label: "已安装版本", value: L.t("%d 个", snapshot.versions.count))
            InfoTile(label: "版本根目录", value: shortPath(snapshot.rootPath))
        }
    }

    private var versionsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.t("已安装版本"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(L.t("默认版本会在新终端中生效"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)

            if snapshot.versions.isEmpty {
                Text(L.t("还没有安装任何 Node 版本"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
            } else {
                ForEach(Array(snapshot.versions.enumerated()), id: \.element.id) { index, version in
                    versionRow(version)
                    if index < snapshot.versions.count - 1 {
                        Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1).padding(.leading, 12)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .cardSurface()
    }

    private func versionRow(_ version: NodeVersionInfo) -> some View {
        HStack(spacing: 9) {
            Image(systemName: version.isDefault ? "hexagon.fill" : "hexagon")
                .font(.system(size: 11))
                .foregroundStyle(version.isDefault ? Theme.green : Theme.textTertiary)
            Text(version.version)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 84, alignment: .leading)
            if version.isDefault {
                TagChip(text: "默认", tint: Theme.green)
            }
            Spacer(minLength: 4)
            if let npm = version.npmVersion {
                Text("npm \(npm)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
            if let size = version.size {
                Text(size)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 62, alignment: .trailing)
            }
            if !version.isDefault {
                PillButton(
                    title: "设为默认",
                    systemImage: "arrow.triangle.swap",
                    tint: Theme.green,
                    kind: .ghost,
                    compact: true,
                    enabled: model.runtimeBusy == nil
                ) {
                    Task { await model.setDefaultNode(version.version) }
                }
            }
            IconButton(systemImage: "trash", size: 20, help: "卸载") {
                pendingUninstall = version.version
            }
            IconButton(systemImage: "folder", size: 20, help: "在 Finder 中显示") {
                model.reveal(version.path)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(of: Shell.home, with: "~")
    }
}

// MARK: - 安装 Node 版本

struct NodeInstallSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var version = ""

    private let presets = ["lts", "latest", "20", "22", "24"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                IconBadge(symbol: "hexagon.fill", tint: Theme.green, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L.t("安装 Node 版本"))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L.t("通过 fnm 下载安装，会放到 ~/.local/share/fnm"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }

            TextField(L.t("版本号，例如 22 / lts / v20.11.0"), text: $version)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            HStack(spacing: 5) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        version = preset
                    } label: {
                        Text(preset)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(version == preset ? Theme.green : Theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(version == preset ? Theme.green.opacity(0.12) : Theme.cardSoft))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            HStack {
                Spacer()
                PillButton(title: "取消", kind: .secondary, compact: true) { dismiss() }
                PillButton(title: "开始安装", systemImage: "arrow.down.circle", tint: Theme.green, kind: .primary, compact: true, enabled: !version.isEmpty) {
                    let target = version
                    dismiss()
                    Task { await model.installNode(target) }
                }
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(Theme.page)
    }
}
