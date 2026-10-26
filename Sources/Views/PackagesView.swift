import SwiftUI

// MARK: - Homebrew 包管理

struct PackagesView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    searchBar
                    if model.brewTab == .installed {
                        installedSection
                    } else {
                        resultSection
                    }
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 30)
            }
        }
        .task {
            if model.brewInstalled.isEmpty {
                await model.loadInstalledPackages()
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            IconBadge(symbol: "shippingbox.fill", tint: Theme.amber, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t("Homebrew 包"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L.t("搜索、安装、卸载 · 已安装 %d 个", model.brewInstalled.count))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                PillButton(title: L.t("刷新"), systemImage: "arrow.clockwise", compact: true, loading: model.brewLoading) {
                    Task { await model.reloadBrewPackages() }
                }
            }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    // MARK: 搜索栏

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                tabChip(L.t("搜索"), active: model.brewTab == .search) {
                    model.brewTab = .search
                    searchFocused = true
                }
                tabChip(L.t("已安装"), active: model.brewTab == .installed) {
                    model.brewTab = .installed
                    Task { await model.loadInstalledPackages() }
                }

                Spacer(minLength: 8)

                kindChip("formula", active: model.brewKind == "formula")
                kindChip("cask", active: model.brewKind == "cask")
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    TextField(L.t("搜索 formula，例如 redis / postgres"), text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($searchFocused)
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

                PillButton(
                    title: L.t("搜索"),
                    systemImage: "magnifyingglass",
                    tint: Theme.amber,
                    kind: .primary,
                    compact: true,
                    loading: model.brewSearching,
                    enabled: !query.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    runSearch()
                }
                .fixedSize()
            }
        }
    }

    private func runSearch() {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return }
        Task { await model.searchBrewPackages(keyword) }
    }

    private func tabChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(active ? Theme.card : Color.clear))
                .overlay(Capsule().strokeBorder(active ? Theme.border : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func kindChip(_ kind: String, active: Bool) -> some View {
        Button {
            model.brewKind = kind
        } label: {
            Text(kind)
                .font(.system(size: 10.5, weight: active ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(active ? Theme.amber : Theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(active ? Theme.amber.opacity(0.12) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: 搜索结果

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.brewSearching {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(L.t("正在搜索…"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else if model.brewResults.isEmpty {
                cardContainer {
                    EmptyStateView(
                        symbol: "shippingbox",
                        title: model.brewLastQuery.isEmpty ? L.t("输入关键词开始搜索") : L.t("没有找到匹配的包"),
                        message: model.brewLastQuery.isEmpty
                            ? L.t("例如 redis、mysql、node、ollama，支持模糊匹配。")
                            : L.t("换个关键词试试，或者切换 formula / cask。")
                    )
                }
            } else {
                SectionLabel(text: L.t("搜索结果"), trailing: L.t("%d 个", model.brewResults.count))
                VStack(spacing: 0) {
                    ForEach(Array(model.brewResults.enumerated()), id: \.element.id) { index, pkg in
                        packageRow(pkg)
                        if index < model.brewResults.count - 1 {
                            Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1).padding(.leading, 12)
                        }
                    }
                }
                .cardSurface()
            }
        }
    }

    // MARK: 已安装

    private var installedSection: some View {
        let list = model.brewInstalled.filter { $0.kind == model.brewKind }
        return VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: L.t("已安装"), trailing: L.t("%d 个", list.count))
            if list.isEmpty {
                cardContainer {
                    EmptyStateView(
                        symbol: "shippingbox",
                        title: L.t("还没有安装任何 %@ 包", model.brewKind),
                        message: L.t("切到「搜索」页找找看，或者用「服务」页安装常用开发服务。")
                    )
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, pkg in
                        packageRow(pkg)
                        if index < list.count - 1 {
                            Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1).padding(.leading, 12)
                        }
                    }
                }
                .cardSurface()
            }
        }
    }

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .cardSurface()
    }

    // MARK: 行

    private func packageRow(_ pkg: BrewPackage) -> some View {
        let busy = model.brewBusy == pkg.id
        return HStack(spacing: 10) {
            IconBadge(symbol: pkg.kind == "cask" ? "app.badge.fill" : "shippingbox.fill",
                      tint: pkg.kind == "cask" ? Theme.purple : Theme.amber, size: 26)
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text(pkg.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if !pkg.displayVersion.isEmpty {
                        Text(pkg.displayVersion)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if pkg.installed, model.brewTab == .search {
                        TagChip(text: L.t("已安装"), tint: Theme.green)
                    }
                }
                if !pkg.summary.isEmpty {
                    Text(pkg.summary)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            if pkg.installed {
                PillButton(title: L.t("卸载"), systemImage: "trash", kind: .danger, compact: true, loading: busy, enabled: model.brewBusy == nil) {
                    Task { await model.uninstallPackage(pkg) }
                }
            } else {
                PillButton(title: L.t("安装"), systemImage: "arrow.down.circle", tint: Theme.amber, kind: .primary, compact: true, loading: busy, enabled: model.brewBusy == nil) {
                    Task { await model.installPackage(pkg) }
                }
            }
            IconButton(systemImage: "terminal", size: 20, help: L.t("在终端查看 info")) {
                model.openInTerminal("brew info \(pkg.kind == "cask" ? "--cask " : "")\(pkg.name)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
