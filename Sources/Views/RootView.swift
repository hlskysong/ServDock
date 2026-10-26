import SwiftUI

// MARK: - 根视图

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                SidebarView()
                Rectangle().fill(Theme.border).frame(width: 1)
                DetailView()
            }
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .background(Theme.page)
        .frame(minWidth: 1010, minHeight: 660)
        .sheet(isPresented: Binding(
            get: { model.inspecting != nil },
            set: { if !$0 { model.inspecting = nil } }
        )) {
            Group {
                if let id = model.inspecting {
                    ServiceDetailView(itemID: id)
                        .environmentObject(model)
                }
            }
        }
        .sheet(isPresented: $model.nodeInstallSheet) {
            NodeInstallSheet()
                .environmentObject(model)
        }
    }
}

// MARK: - 侧边栏

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    navRow(.overview, L.t("总览"), "square.grid.2x2.fill",
                           badge: "\(model.runningCount)/\(model.installedItems().count)",
                           badgeTint: model.runningCount > 0 ? Theme.green : Theme.textTertiary)

                    groupLabel(L.t("服务"))
                        .padding(.top, 12)

                    ForEach(ServiceCategory.allCases) { category in
                        let stat = model.count(category: category)
                        navRow(.category(category), category.title, category.symbol,
                               badge: stat.total > 0 ? "\(stat.running)/\(stat.total)" : nil,
                               badgeTint: stat.running > 0 ? Theme.green : Theme.textTertiary)
                    }

                    groupLabel(L.t("系统"))
                        .padding(.top, 12)

                    navRow(.timers, L.t("定时任务"), "clock.badge.checkmark",
                           badge: model.timers.jobs.isEmpty ? nil : "\(model.timerRunningCount)/\(model.timers.jobs.count)",
                           badgeTint: model.timerRunningCount > 0 ? Theme.green : Theme.textTertiary)

                    navRow(.docker, L.t("容器"), "shippingbox.fill",
                           badge: model.docker.containers.isEmpty ? nil : "\(model.docker.runningCount)/\(model.docker.containers.count)",
                           badgeTint: model.docker.runningCount > 0 ? Theme.green : Theme.textTertiary)

                    navRow(.packages, L.t("Homebrew 包"), "shippingbox.circle.fill",
                           badge: model.brewInstalled.isEmpty ? nil : "\(model.brewInstalled.count)",
                           badgeTint: Theme.textTertiary)

                    groupLabel(L.t("运行时"))
                        .padding(.top, 12)

                    navRow(.bun, "Bun", "hare.fill",
                           badge: model.bun.installed ? model.bun.version : nil,
                           badgeTint: Theme.textTertiary)

                    navRow(.node, "Node.js", "hexagon.fill",
                           badge: model.node.defaultVersion.map { shortVersion($0) },
                           badgeTint: Theme.textTertiary)

                    navRow(.mise, "mise", "wrench.and.screwdriver.fill",
                           badge: model.mise.version.isEmpty ? nil : "\(model.mise.toolNames.count)",
                           badgeTint: Theme.textTertiary)

                    groupLabel(L.t("工具"))
                        .padding(.top, 12)

                    navRow(.easytier, "EasyTier", "globe.asia.australia.fill",
                           badge: model.easyTier.peers.isEmpty ? nil : "\(model.easyTier.peers.count)",
                           badgeTint: model.easyTier.reachable ? Theme.green : Theme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(width: Metrics.sidebarWidth)
        .background(Theme.sidebar)
    }

    private var brand: some View {
        HStack(spacing: 9) {
            IconBadge(symbol: "shippingbox.fill", tint: Theme.accent, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(L.t("启服"))
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L.t("本地服务控制台"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            IconButton(systemImage: "gearshape", size: 22, help: L.t("设置")) {
                model.selection = .settings
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 30)
        .padding(.bottom, 14)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .textCase(.uppercase)
            .padding(.horizontal, 9)
            .padding(.bottom, 4)
    }

    private func navRow(_ item: NavItem, _ title: String, _ symbol: String,
                        badge: String? = nil, badgeTint: Color = Theme.textTertiary) -> some View {
        SidebarRow(
            title: title,
            symbol: symbol,
            badge: badge,
            badgeTint: badgeTint,
            isSelected: model.selection == item
        ) {
            model.selection = item
            if item == .packages, model.brewInstalled.isEmpty {
                Task { await model.loadInstalledPackages() }
            }
            if item == .easytier {
                Task { await model.loadEasyTier() }
            }
            if item == .docker {
                Task { await model.loadDocker() }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 5) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
                Text("Homebrew \(model.brewVersionText)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if model.update.hasUpdate, !model.updateSkipped {
                    updateBadge
                }
                langButton
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                        .frame(width: 10, height: 10)
                }
            }
            Text(model.lastRefresh.map { L.t("更新于 %@", TimeText.clock($0)) } ?? L.t("等待首次刷新"))
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 13)
        .padding(.top, 9)
        .padding(.bottom, 11)
    }

    /// 有新版本时侧栏底部直接给个入口（点了进设置页）
    private var updateBadge: some View {
        Button {
            model.selection = .settings
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 8.5, weight: .bold))
                Text(model.update.latest)
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.amber)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.amber.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help(L.t("有新版本 %@", model.update.latest))
    }

    /// 侧栏底部一键切中英
    private var langButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                model.setLanguage(model.lang == .zh ? .en : .zh)
            }
        } label: {
            Text(model.lang.badge)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(model.lang == .zh ? "Switch to English" : "切换到中文")
    }

    private func shortVersion(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }
}

struct SidebarRow: View {
    var title: String
    var symbol: String
    var badge: String?
    var badgeTint: Color
    var isSelected: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(badgeTint)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Theme.selection : (hovering ? Theme.card.opacity(0.55) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - 详情路由

struct DetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.selection {
            case .overview:
                DashboardView(scope: nil)
            case .category(let category):
                DashboardView(scope: category)
            case .timers:
                TimersView()
            case .docker:
                DockerView()
            case .bun:
                BunView()
            case .node:
                NodeView()
            case .easytier:
                EasyTierView()
            case .packages:
                PackagesView()
            case .mise:
                MiseView()
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page)
    }
}

// MARK: - 时间格式

enum TimeText {
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }
    static func stamp(_ date: Date) -> String { dateFormatter.string(from: date) }
}
