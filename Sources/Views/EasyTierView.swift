import SwiftUI
import AppKit

// MARK: - EasyTier 组网

struct EasyTierView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAllPeers = false

    private var item: ServiceItem? { model.item("easytier") }
    private var snap: EasyTierSnapshot { model.easyTier }

    /// 服务是否在跑：进程表命中，或 RPC 已经能读到节点（GUI 守护进程不在 launchd 里，用 RPC 兜底判断）
    private var isUp: Bool { item?.isRunning == true || snap.reachable }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let busy = model.etBusy {
                        busyBanner(busy)
                    }
                    statusCard
                    if !snap.cliReady {
                        cliCard
                    } else if !snap.reachable {
                        unreachableCard
                    }
                    if snap.cliReady, !snap.peers.isEmpty {
                        peerSection
                    }
                    if snap.cliReady, let node = snap.node {
                        detailSection(node)
                    }
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 30)
            }
        }
        .task {
            if model.easyTier.collectedAt.timeIntervalSince1970 == 0 {
                await model.loadEasyTier()
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            IconBadge(symbol: "globe.asia.australia.fill", tint: Theme.teal, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("EasyTier")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    if let node = snap.node, !node.version.isEmpty {
                        Text(node.version)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.cardSoft))
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if item != nil {
                    if isUp {
                        PillButton(title: L.t("停止"), systemImage: "stop.fill", kind: .danger, compact: true, enabled: model.etBusy == nil) {
                            model.perform(.stop, on: "easytier")
                        }
                        PillButton(title: L.t("重启"), systemImage: "arrow.triangle.2.circlepath", compact: true, enabled: model.etBusy == nil) {
                            model.perform(.restart, on: "easytier")
                        }
                    } else {
                        PillButton(title: L.t("启动"), systemImage: "play.fill", tint: Theme.green, kind: .primary, compact: true, enabled: model.etBusy == nil) {
                            model.perform(.start, on: "easytier")
                        }
                    }
                }
                PillButton(title: L.t("刷新"), systemImage: "arrow.clockwise", compact: true, loading: model.etRefreshing) {
                    Task { await model.loadEasyTier() }
                }
            }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        if let node = snap.node {
            if node.networkName.isEmpty { return L.t("去中心化 P2P 组网 · %d 个节点", snap.peers.count) }
            return L.t("网络 %@ · %d 个节点", node.networkName, snap.peers.count)
        }
        if isUp {
            return L.t("守护进程在运行，但没有拿到节点信息")
        }
        return L.t("去中心化 P2P 组网 / 虚拟局域网")
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

    // MARK: 状态卡

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                IconBadge(symbol: "globe.asia.australia.fill", tint: Theme.teal, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(isUp ? L.t("运行中") : L.t("未运行"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(isUp ? Theme.green : Theme.textSecondary)
                        if let node = snap.node, !node.hostname.isEmpty {
                            Text(node.hostname)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    Text(rpcText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 8)
                if let node = snap.node {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(node.bareIPv4)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.teal)
                            .textSelection(.enabled)
                        Text(L.t("本机虚拟 IP"))
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    IconButton(systemImage: "doc.on.doc", size: 22, help: L.t("复制地址")) {
                        model.copyToPasteboard(node.bareIPv4, label: L.t("虚拟 IP"))
                    }
                }
            }

            if let node = snap.node {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 9)], spacing: 9) {
                    InfoTile(label: L.t("主机名"), value: node.hostname.isEmpty ? "—" : node.hostname, mono: true)
                    InfoTile(label: L.t("NAT 类型"), value: node.natType.isEmpty ? "—" : node.natType, mono: true)
                    InfoTile(label: L.t("网络"), value: node.networkName.isEmpty ? "—" : node.networkName, mono: true)
                    InfoTile(label: L.t("节点数"), value: "\(snap.peers.count)")
                    InfoTile(label: L.t("公网 IP"),
                             value: node.publicIPs.first ?? "—",
                             mono: true)
                    InfoTile(label: L.t("RPC 端口"), value: snap.rpcPortal, mono: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var rpcText: String {
        if let pid = item?.pid {
            return L.t("RPC %@ · PID %d", snap.rpcPortal, pid)
        }
        if snap.reachable {
            return L.t("RPC %@ · 已连接", snap.rpcPortal)
        }
        return L.t("RPC %@", snap.rpcPortal)
    }

    // MARK: 未装 CLI / 连不上

    private var cliCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("需要 easytier-cli 才能读取节点信息"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L.t("EasyTier 的节点状态只能通过 easytier-cli 查询。启服会自动下载到本地缓存目录，不写入系统路径。"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                PillButton(title: L.t("下载 CLI"), systemImage: "arrow.down.circle", tint: Theme.teal, kind: .primary, compact: true, loading: model.etCliInstalling) {
                    Task { await model.installEasyTierCLI() }
                }
            }
            Text(EasyTierProbe.binDir + "/easytier-cli")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.amber.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.amber.opacity(0.22), lineWidth: 1))
    }

    private var unreachableCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text(isUp ? L.t("无法连接 EasyTier RPC") : L.t("EasyTier 没有运行"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(snap.error ?? L.t("启动守护进程后即可查看节点信息"))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 节点表

    private var peerSection: some View {
        let visible = showAllPeers ? snap.peers : Array(snap.peers.prefix(8))
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: L.t("节点信息"), trailing: L.t("%d 个节点", snap.peers.count))
                if snap.peers.count > 8 {
                    Button(showAllPeers ? L.t("收起") : L.t("展开全部")) {
                        withAnimation(.easeInOut(duration: 0.16)) { showAllPeers.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
            }

            VStack(spacing: 0) {
                peerHeaderRow
                Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, peer in
                    peerRow(peer, index: index)
                    if index < visible.count - 1 {
                        Rectangle().fill(Theme.border.opacity(0.4)).frame(height: 1)
                    }
                }
            }
            .cardSurface()
        }
    }

    private var peerHeaderRow: some View {
        HStack(spacing: 8) {
            headerCell(L.t("虚拟 IPv4"), width: 122)
            headerCell(L.t("主机名"), width: nil)
            headerCell(L.t("路由"), width: 52)
            headerCell(L.t("协议"), width: 50)
            headerCell(L.t("延迟"), width: 58)
            headerCell(L.t("上传"), width: 74)
            headerCell(L.t("下载"), width: 74)
            headerCell(L.t("丢包"), width: 52)
            headerCell(L.t("NAT"), width: 78)
            headerCell(L.t("版本"), width: 92)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.cardSoft)
    }

    @ViewBuilder
    private func headerCell(_ text: String, width: CGFloat?) -> some View {
        let label = Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
        if let width {
            label.frame(width: width, alignment: .leading)
        } else {
            label.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func peerRow(_ peer: ETPeer, index: Int) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(peer.isLocal ? Theme.teal : Theme.green)
                    .frame(width: 5, height: 5)
                Text(peer.ipv4)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            .frame(width: 122, alignment: .leading)

            Text(peer.hostname)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            TagChip(text: peer.routeText, tint: peer.isLocal ? Theme.teal : (peer.cost.lowercased() == "relay" ? Theme.amber : Theme.green))
                .frame(width: 52, alignment: .leading)

            Text(peer.proto)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 50, alignment: .leading)

            Text(latencyText(peer))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(latencyColor(peer))
                .frame(width: 58, alignment: .leading)

            Text(peer.rx)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 74, alignment: .leading)

            Text(peer.tx)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 74, alignment: .leading)

            Text(peer.lossRate)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(peer.lossRate == "-" || peer.lossRate.hasPrefix("0") ? Theme.textTertiary : Theme.red)
                .frame(width: 52, alignment: .leading)

            Text(peer.natType)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)

            Text(peer.version)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 92, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6.5)
        .background(index % 2 == 1 ? Theme.cardSoft.opacity(0.5) : Color.clear)
        .contextMenu {
            Button(L.t("复制 IP")) { model.copyToPasteboard(peer.ipv4, label: L.t("IP")) }
            if !peer.hostname.isEmpty {
                Button(L.t("复制主机名")) { model.copyToPasteboard(peer.hostname, label: L.t("主机名")) }
            }
            Button(L.t("在终端中 ping")) { model.openInTerminal("ping -c 4 \(peer.ipv4)") }
        }
    }

    private func latencyText(_ peer: ETPeer) -> String {
        if peer.isLocal { return L.t("本机") }
        return peer.latency == "-" ? "—" : "\(peer.latency) ms"
    }

    private func latencyColor(_ peer: ETPeer) -> Color {
        guard !peer.isLocal, let value = Double(peer.latency) else { return Theme.textTertiary }
        if value < 5 { return Theme.green }
        if value < 40 { return Theme.textSecondary }
        return Theme.amber
    }

    // MARK: 详情

    private func detailSection(_ node: ETNodeInfo) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: L.t("本机详情"))
            VStack(spacing: 0) {
                if !node.listeners.isEmpty {
                    KeyValueRow(label: L.t("监听"), value: node.listeners.joined(separator: "  "), mono: true)
                }
                if !node.publicIPs.isEmpty {
                    KeyValueRow(label: L.t("公网 IP"), value: node.publicIPs.joined(separator: ", "), mono: true)
                }
                if let pid = item?.pid {
                    KeyValueRow(label: "PID", value: "\(pid)", mono: true)
                }
                KeyValueRow(label: L.t("配置文件"), value: configDirText, mono: true, copyable: true) {
                    model.copyToPasteboard(configDirText, label: L.t("配置目录"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .cardSurface()
        }
    }

    private var configDirText: String {
        let dir = Shell.home + "/Library/Application Support/com.kkrainbow.easytier/config.d"
        return dir.replacingOccurrences(of: Shell.home, with: "~")
    }
}
