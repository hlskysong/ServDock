import SwiftUI

struct ServiceCard: View {
    let item: ServiceItem

    @EnvironmentObject var model: AppModel
    @State private var hovering = false

    private var tint: Color { item.spec.category.tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            topRow
            metaRow
            if let error = item.lastError {
                noticeRow(text: error, tint: Theme.red, symbol: "exclamationmark.triangle.fill")
            } else if let conflict = item.portConflict {
                noticeRow(text: conflict, tint: Theme.amber, symbol: "exclamationmark.circle.fill")
            }
            Spacer(minLength: 0)
            actionRow
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
        .cardSurface(hovering: hovering)
        .overlay {
            if item.busy {
                ZStack {
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .fill(Theme.card.opacity(0.78))
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text(item.busyText.isEmpty ? L.t("处理中…") : item.busyText)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hovering = value }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.inspecting = item.id }
        .contextMenu { contextMenu }
    }

    // MARK: 头部

    private var topRow: some View {
        HStack(alignment: .top, spacing: 9) {
            IconBadge(symbol: ServiceGlyph.symbol(for: item.id), tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(item.versionText)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Theme.cardSoft))
                }
                Text(L.t(item.spec.summary))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            StatusPill(status: item.status)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 9) {
            if item.installed {
                metaItem(symbol: "network", text: item.portText)
            }
            if let pid = item.pid {
                metaItem(symbol: "cpu", text: "PID \(pid)")
            }
            if item.loginItem {
                TagChip(text: "开机自启", tint: Theme.blue)
            }
            if let tag = item.kindTag {
                TagChip(text: tag, tint: Theme.slate)
            }
            Spacer(minLength: 0)
            if hovering, let address = item.address {
                IconButton(systemImage: "doc.on.doc", size: 18, help: "复制地址") {
                    model.copyToPasteboard(address, label: "地址")
                }
            }
        }
        .frame(height: 16)
    }

    private func metaItem(symbol: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private func noticeRow(text: String, tint: Color, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .semibold))
            Text(text)
                .font(.system(size: 9.5))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 操作

    private var actionRow: some View {
        HStack(spacing: 5) {
            primaryButton
            PillButton(
                title: "重启",
                systemImage: "arrow.triangle.2.circlepath",
                compact: true,
                enabled: item.isRunning && !item.busy
            ) {
                model.perform(.restart, on: item.id)
            }
            Spacer(minLength: 0)
            IconButton(systemImage: "info.circle", size: 22, help: "详情") {
                model.inspecting = item.id
            }
            if let url = item.webURL {
                IconButton(systemImage: "safari", size: 22, help: "在浏览器打开") {
                    model.openURL(url)
                }
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if !item.installed {
            PillButton(
                title: item.spec.installURL != nil ? L.t("下载") : L.t("安装"),
                systemImage: item.spec.installURL != nil ? "arrow.up.right.square" : "arrow.down.circle",
                kind: .primary,
                compact: true,
                loading: item.busy
            ) {
                Task { await model.installService(item.id) }
            }
        } else if item.isRunning {
            PillButton(
                title: "停止",
                systemImage: "stop.fill",
                kind: .danger,
                compact: true,
                enabled: !item.busy
            ) {
                model.perform(.stop, on: item.id)
            }
        } else {
            PillButton(
                title: "启动",
                systemImage: "play.fill",
                tint: Theme.green,
                kind: .primary,
                compact: true,
                enabled: !item.busy,
                help: "启动并加入登录自启"
            ) {
                model.perform(.start, on: item.id)
            }
        }
    }

    // MARK: 右键菜单

    @ViewBuilder
    private var contextMenu: some View {
        if item.installed {
            if item.isRunning {
                Button(L.t("停止")) { model.perform(.stop, on: item.id) }
                Button(L.t("重启")) { model.perform(.restart, on: item.id) }
            } else {
                Button(L.t("启动（含开机自启）")) { model.perform(.start, on: item.id) }
                if item.supportsRun {
                    Button(L.t("仅本次启动")) { model.perform(.run, on: item.id) }
                }
            }
            Divider()
        }
        Button(L.t("查看详情…")) { model.inspecting = item.id }
        if let address = item.address {
            Button(L.t("复制地址")) { model.copyToPasteboard(address, label: "地址") }
        }
        if let config = item.spec.configPaths().first {
            Button(L.t("在 Finder 中显示配置")) { model.reveal(config) }
        }
        Button(L.t("在终端中查看状态")) {
            model.openInTerminal(item.statusCommand)
        }
    }
}
