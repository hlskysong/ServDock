import SwiftUI

struct DashboardView: View {
    let scope: ServiceCategory?

    @EnvironmentObject var model: AppModel
    @State private var showAllInstallable = false

    private var title: String { scope?.title ?? L.t("总览") }

    private var subtitle: String {
        if let scope {
            let stat = model.count(category: scope)
            return L.t("%d 运行中 · 共 %d 个已安装", stat.running, stat.total)
        }
        let installed = model.installedItems().count
        return L.t("本机开发服务 · 已安装 %d 个，运行中 %d 个", installed, model.runningCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    statsRow
                    serviceSection
                    installableSection
                    hintRow
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 12)
            SearchField(text: $model.searchText)
            PillButton(
                title: "仅运行中",
                systemImage: model.showOnlyRunning ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                tint: Theme.green,
                kind: model.showOnlyRunning ? .ghost : .secondary,
                compact: true
            ) {
                model.showOnlyRunning.toggle()
            }
            IconButton(systemImage: "arrow.clockwise", size: 26, help: "刷新（⌘R）") {
                Task { await model.refresh(runtimes: true) }
            }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    private var hintRow: some View {
        Text(L.t("双击卡片查看日志与配置文件 · 右键卡片可快速启停"))
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
    }

    // 统计口径跟随当前范围
    private var scopeItems: [ServiceItem] {
        guard let scope else { return model.items }
        return model.items(in: scope)
    }

    private var runningCount: Int { scopeItems.filter { $0.isRunning }.count }
    private var installedCount: Int { scopeItems.filter { $0.installed }.count }
    private var problemCount: Int { scopeItems.filter { $0.status.isProblem }.count }
    private var installableCount: Int { scopeItems.filter { !$0.installed }.count }

    private var statsRow: some View {
        HStack(spacing: 9) {
            metric(L.t("运行中"), "\(runningCount)", Theme.green, "play.circle.fill")
            metric(L.t("已安装"), "\(installedCount)", Theme.blue, "shippingbox.fill")
            metric(L.t("异常"), "\(problemCount)", problemCount > 0 ? Theme.red : Theme.textTertiary, "exclamationmark.triangle.fill")
            metric(L.t("可安装"), "\(installableCount)", Theme.purple, "arrow.down.circle.fill")
            Spacer(minLength: 0)
        }
    }

    private func metric(_ label: String, _ value: String, _ tint: Color, _ symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    // MARK: 服务卡片

    private var serviceSection: some View {
        let list = model.visibleItems(scope: scope)
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "已安装服务", trailing: list.isEmpty ? nil : L.t("%d 个", list.count))
            if list.isEmpty {
                cardContainer {
                    EmptyStateView(
                        symbol: "shippingbox",
                        title: model.searchText.isEmpty ? "还没有已安装的服务" : "没有匹配的服务",
                        message: model.searchText.isEmpty
                            ? "从下方「可安装服务」里挑选，或直接用 brew install 安装。"
                            : "换个关键词试试。"
                    )
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 316, maximum: 470), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(list) { item in
                        ServiceCard(item: item)
                    }
                }
            }
        }
    }

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .cardSurface()
    }

    // MARK: 可安装

    private var installableSection: some View {
        let pool = model.uninstalledItems().filter { item in
            if let scope, item.spec.category != scope { return false }
            guard !model.searchText.isEmpty else { return true }
            let keyword = model.searchText.lowercased()
            return item.title.lowercased().contains(keyword) || item.id.lowercased().contains(keyword)
        }
        let visible = showAllInstallable ? pool : Array(pool.prefix(5))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "可安装服务", trailing: L.t("%d 个", pool.count))
                if pool.count > 5 {
                    Button(showAllInstallable ? L.t("收起") : L.t("展开全部")) {
                        withAnimation(.easeInOut(duration: 0.16)) { showAllInstallable.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
            }

            if pool.isEmpty {
                cardContainer {
                    EmptyStateView(symbol: "checkmark.seal", title: "内置服务清单都已安装", message: "可以用搜索或命令行动手安装其他 formula。")
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                        installRow(item)
                        if index < visible.count - 1 {
                            Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1).padding(.leading, 40)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .cardSurface()
            }
        }
    }

    private func installRow(_ item: ServiceItem) -> some View {
        HStack(spacing: 9) {
            IconBadge(symbol: ServiceGlyph.symbol(for: item.id), tint: item.spec.category.tint, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(L.t(item.spec.summary))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            PillButton(
                title: item.busy ? (item.busyText.isEmpty ? L.t("安装中…") : item.busyText) : L.t("安装"),
                systemImage: "arrow.down.circle",
                compact: true,
                loading: item.busy
            ) {
                Task { await model.installService(item.id) }
            }
            .frame(width: 78, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
    }
}
