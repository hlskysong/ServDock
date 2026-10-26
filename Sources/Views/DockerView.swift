import SwiftUI

// MARK: - Docker / OrbStack 管理

struct DockerView: View {
    @EnvironmentObject var model: AppModel

    private var snap: DockerSnapshot { model.docker }
    private var busy: Bool { model.dockerBusy != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let text = model.dockerBusy {
                        busyBanner(text)
                    }
                    if !snap.installed {
                        notInstalledCard
                    } else {
                        statusCard
                        if !snap.daemonRunning {
                            daemonDownCard
                        } else {
                            tabBar
                            if model.dockerTab == .containers {
                                containersSection
                            } else {
                                imagesSection
                            }
                        }
                    }
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 30)
            }
        }
        .task {
            if snap.cliPath == nil {
                await model.loadDocker()
            }
        }
        .sheet(item: $model.dockerSheet) { container in
            DockerLogSheet(container: container)
                .environmentObject(model)
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            IconBadge(symbol: "shippingbox.fill", tint: Theme.blue, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("Docker")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    if !snap.engine.isEmpty {
                        Text(snap.engine)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.cardSoft))
                    }
                    if !snap.serverVersion.isEmpty {
                        TagChip(text: snap.serverVersion, tint: Theme.blue)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if snap.hasOrb {
                    if snap.orbIsRunning {
                        PillButton(title: L.t("停止 OrbStack"), systemImage: "stop.fill", kind: .danger, compact: true, loading: busy) {
                            Task { await model.stopOrb() }
                        }
                    } else {
                        PillButton(title: L.t("启动 OrbStack"), systemImage: "play.fill", tint: Theme.blue, kind: .primary, compact: true, loading: busy) {
                            Task { await model.startOrb() }
                        }
                    }
                }
                PillButton(title: L.t("刷新"), systemImage: "arrow.clockwise", compact: true, loading: model.dockerLoading) {
                    Task { await model.loadDocker() }
                }
            }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        if !snap.installed { return L.t("未检测到 docker 命令") }
        if !snap.daemonRunning { return L.t("守护进程没有响应") }
        return L.t("%d 个容器（%d 个运行中） · %d 个镜像", snap.containers.count, snap.runningCount, snap.images.count)
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
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.blue.opacity(0.08)))
    }

    // MARK: 未安装

    private var notInstalledCard: some View {
        VStack(spacing: 12) {
            EmptyStateView(
                symbol: "shippingbox",
                title: L.t("没有找到 docker 命令"),
                message: L.t("服务坞通过 docker CLI 管理容器。装 OrbStack 或 Docker Desktop 后重新打开本页即可。"),
                actionTitle: L.t("重新检测"),
                action: { Task { await model.loadDocker() } }
            )
        }
        .cardSurface()
    }

    // MARK: 状态

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(snap.daemonRunning ? Theme.green : Theme.textTertiary)
                    .frame(width: 8, height: 8)
                Text(snap.daemonRunning ? L.t("守护进程运行中") : L.t("守护进程未运行"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(snap.daemonRunning ? Theme.textPrimary : Theme.textSecondary)
                if snap.hasOrb {
                    TagChip(text: L.t("OrbStack %@", snap.orbIsRunning ? L.t("运行中") : L.t("已停止")),
                            tint: snap.orbIsRunning ? Theme.green : Theme.amber)
                }
                Spacer(minLength: 6)
                Text(snap.cliPath.map(shortPath) ?? "")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
                InfoTile(label: L.t("容器"), value: "\(snap.containers.count)")
                InfoTile(label: L.t("运行中"), value: "\(snap.runningCount)",
                         tint: snap.runningCount > 0 ? Theme.green : Theme.textTertiary)
                InfoTile(label: L.t("镜像"), value: "\(snap.images.count)")
                InfoTile(label: L.t("镜像占用"), value: snap.diskTotal.isEmpty ? "—" : snap.diskTotal)
            }
            .opacity(snap.daemonRunning ? 1 : 0.45)

            if snap.daemonRunning, !snap.diskReclaimable.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                    Text(L.t("可回收空间 %@", snap.diskReclaimable))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 守护进程没起

    private var daemonDownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.amber)
                Text(L.t("容器引擎没有运行"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 6)
                if snap.hasOrb {
                    TagChip(text: "OrbStack", tint: Theme.blue)
                }
            }

            Text(snap.hasOrb
                 ? L.t("docker CLI 在，但 OrbStack 的引擎没起来。点下面的按钮启动它，或直接用 orb start。")
                 : L.t("docker CLI 在，但引擎没起来。请先启动 Docker Desktop / colima，再回来刷新。"))
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if snap.hasOrb {
                    PillButton(title: L.t("启动 OrbStack"), systemImage: "play.fill", tint: Theme.blue, kind: .primary, compact: true, loading: busy) {
                        Task { await model.startOrb() }
                    }
                    .fixedSize()
                }
                PillButton(title: L.t("重新检测"), systemImage: "arrow.clockwise", compact: true, loading: model.dockerLoading) {
                    Task { await model.loadDocker() }
                }
                .fixedSize()
                Spacer(minLength: 0)
            }

            if let error = snap.errorText, !error.isEmpty {
                Text(error)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.amber.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.amber.opacity(0.28), lineWidth: 1))
    }

    // MARK: 分段

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(AppModel.DockerTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) { model.dockerTab = tab }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(model.dockerTab == tab ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(model.dockerTab == tab ? Theme.card : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.cardSoft))
    }

    // MARK: 容器

    private var containersSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: L.t("容器"), trailing: L.t("%d 个", snap.containers.count))

            if snap.containers.isEmpty {
                EmptyStateView(
                    symbol: "shippingbox",
                    title: L.t("还没有容器"),
                    message: L.t("docker run 出来的容器会出现在这里。")
                )
                .frame(maxWidth: .infinity)
                .cardSurface()
            } else {
                VStack(spacing: 0) {
                    containerHeader
                    Rectangle().fill(Theme.border).frame(height: 1)
                    ForEach(Array(snap.containers.enumerated()), id: \.element.id) { index, container in
                        containerRow(container, striped: index.isMultiple(of: 2) == false)
                        if index < snap.containers.count - 1 {
                            Rectangle().fill(Theme.border.opacity(0.4)).frame(height: 1)
                        }
                    }
                }
                .cardSurface()
            }
        }
    }

    private var containerHeader: some View {
        HStack(spacing: 0) {
            Text(L.t("名称"))
                .frame(width: 150, alignment: .leading)
            Text(L.t("镜像"))
                .frame(width: 168, alignment: .leading)
            Text(L.t("状态"))
                .frame(width: 118, alignment: .leading)
            Text(L.t("端口"))
                .frame(width: 132, alignment: .leading)
            Text(L.t("运行时长"))
                .frame(width: 96, alignment: .leading)
            Spacer(minLength: 4)
            Text(L.t("操作")).frame(width: 150, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func containerRow(_ container: DockerContainer, striped: Bool) -> some View {
        let busy = model.dockerBusy != nil
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(container.isRunning ? Theme.green : (container.isPaused ? Theme.amber : Theme.textTertiary))
                    .frame(width: 6, height: 6)
                Text(container.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)

            Text(container.image)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 168, alignment: .leading)

            Text(container.shortStatus)
                .font(.system(size: 10.5))
                .foregroundStyle(container.isRunning ? Theme.green : Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 118, alignment: .leading)

            Text(container.shortPorts)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .frame(width: 132, alignment: .leading)

            Text(container.runningFor)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                if container.isRunning {
                    PillButton(title: L.t("停止"), systemImage: "stop.fill", kind: .danger, compact: true, enabled: !busy) {
                        Task { await model.stopContainer(container) }
                    }
                    // 重启用图标：中英文长度差异大，文字胶囊会把列撑开
                    IconButton(systemImage: "arrow.clockwise", size: 20, help: L.t("重启")) {
                        Task { await model.restartContainer(container) }
                    }
                } else {
                    PillButton(title: L.t("启动"), systemImage: "play.fill", tint: Theme.blue, kind: .primary, compact: true, enabled: !busy) {
                        Task { await model.startContainer(container) }
                    }
                    IconButton(systemImage: "arrow.clockwise", size: 20, help: L.t("重启")) {
                        Task { await model.restartContainer(container) }
                    }
                }
                IconButton(systemImage: "doc.text.magnifyingglass", size: 20, help: L.t("查看日志")) {
                    model.dockerSheet = container
                }
                IconButton(systemImage: "trash", size: 20, help: L.t("删除容器")) {
                    Task { await model.removeContainer(container) }
                }
            }
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(striped ? Theme.cardSoft.opacity(0.45) : Color.clear)
        .contextMenu {
            Button(L.t("复制名称")) { model.copyToPasteboard(container.name, label: L.t("名称")) }
            Button(L.t("复制 ID")) { model.copyToPasteboard(container.id, label: "ID") }
            if !container.ports.isEmpty {
                Button(L.t("复制端口")) { model.copyToPasteboard(container.ports, label: L.t("端口")) }
            }
        }
    }

    // MARK: 镜像

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: L.t("镜像"), trailing: L.t("%d 个", snap.images.count))

            if snap.images.isEmpty {
                EmptyStateView(
                    symbol: "square.stack.3d.up",
                    title: L.t("还没有镜像"),
                    message: L.t("docker pull 下来的镜像会出现在这里。")
                )
                .frame(maxWidth: .infinity)
                .cardSurface()
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text(L.t("镜像")).frame(width: 300, alignment: .leading)
                        Text(L.t("大小")).frame(width: 90, alignment: .leading)
                        Text(L.t("创建")).frame(width: 130, alignment: .leading)
                        Text("ID").frame(width: 110, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)

                    Rectangle().fill(Theme.border).frame(height: 1)

                    ForEach(Array(snap.images.enumerated()), id: \.element.id) { index, image in
                        HStack(spacing: 0) {
                            Text(image.label)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(image.hasRepo ? Theme.textPrimary : Theme.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: 300, alignment: .leading)
                            Text(image.size)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 90, alignment: .leading)
                            Text(image.createdSince)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                                .frame(width: 130, alignment: .leading)
                            Text(image.shortID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 110, alignment: .leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(index.isMultiple(of: 2) == false ? Theme.cardSoft.opacity(0.45) : Color.clear)
                        .contextMenu {
                            Button(L.t("复制镜像名")) { model.copyToPasteboard(image.label, label: L.t("镜像")) }
                        }
                    }
                }
                .cardSurface()
            }
        }
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(of: Shell.home, with: "~")
    }
}

// MARK: - 日志

struct DockerLogSheet: View {
    let container: DockerContainer
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IconBadge(symbol: "doc.text.magnifyingglass", tint: Theme.blue, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(container.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L.t("最近 200 行日志"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                PillButton(title: L.t("刷新"), systemImage: "arrow.clockwise", compact: true, loading: loading) {
                    Task { await load() }
                }
            }

            if loading {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(L.t("正在读取日志…"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    Text(text.isEmpty ? L.t("（没有日志输出）") : text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 300)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardSoft))
            }

            HStack {
                PillButton(title: L.t("复制全部"), systemImage: "doc.on.doc", compact: true) {
                    model.copyToPasteboard(text, label: L.t("日志"))
                }
                Spacer()
                PillButton(title: L.t("关闭"), compact: true) { dismiss() }
            }
        }
        .padding(18)
        .frame(width: 620)
        .background(Theme.page)
        .task { await load() }
    }

    private func load() async {
        loading = true
        let id = container.id
        let value = await Task.detached(priority: .userInitiated) {
            DockerProbe.logs(id: id)
        }.value
        text = value
        loading = false
    }
}
