import SwiftUI

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    languageSection
                    updateSection
                    aboutSection
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 30)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: "gearshape.fill", tint: Theme.slate, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t("设置"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L.t("界面语言与应用信息"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: L.t("界面语言"), trailing: nil)
            HStack(spacing: 9) {
                ForEach(Lang.allCases) { lang in
                    languageCard(lang)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func languageCard(_ lang: Lang) -> some View {
        let active = model.lang == lang
        return Button {
            model.setLanguage(lang)
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? Theme.accent.opacity(0.14) : Theme.cardSoft)
                    Text(lang.badge)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(lang.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L.t(lang == .zh ? "中文界面" : "英文界面"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 4)
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(active ? Theme.accent : Theme.borderStrong)
            }
            .padding(10)
            .frame(width: 208, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(active ? Theme.accent.opacity(0.06) : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(active ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 版本更新

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: L.t("版本更新"), trailing: updateTintText)
            VStack(spacing: 0) {
                KeyValueRow(label: L.t("当前版本"), value: "\(Brand.version) (\(Brand.buildNumber))", mono: true)
                divider
                KeyValueRow(label: L.t("最新版本"), value: latestVersionText, mono: true)
                if !model.update.publishedAt.isEmpty, model.update.state != .idle {
                    divider
                    KeyValueRow(label: L.t("发布时间"), value: shortDate(model.update.publishedAt))
                }
                if let checked = model.update.checkedAt {
                    divider
                    KeyValueRow(label: L.t("上次检查"), value: TimeText.stamp(checked))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .cardSurface()

            if model.update.hasUpdate, !model.update.notes.isEmpty {
                releaseNotes
            }

            HStack(spacing: 6) {
                PillButton(
                    title: "检查更新",
                    systemImage: "arrow.triangle.2.circlepath",
                    compact: true,
                    loading: model.updateChecking
                ) {
                    Task { await model.checkUpdate() }
                }
                if model.update.hasUpdate {
                    PillButton(
                        title: model.update.canSelfInstall ? "下载并安装" : "打开发布页",
                        systemImage: model.update.canSelfInstall ? "arrow.down.circle.fill" : "safari",
                        kind: .primary,
                        compact: true,
                        loading: model.updateInstalling
                    ) {
                        if model.update.canSelfInstall {
                            Task { await model.installUpdate() }
                        } else {
                            model.openReleasePage()
                        }
                    }
                    if model.update.canSelfInstall {
                        PillButton(title: "打开发布页", systemImage: "safari", compact: true) {
                            model.openReleasePage()
                        }
                    }
                    PillButton(
                        title: model.updateSkipped ? "取消跳过" : "跳过此版本",
                        systemImage: model.updateSkipped ? "arrow.uturn.backward" : "bell.slash",
                        kind: .ghost,
                        compact: true
                    ) {
                        if model.updateSkipped {
                            model.unskipUpdate()
                        } else {
                            model.skipUpdate()
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private var releaseNotes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t("更新说明"))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(model.update.notes)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.cardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private var latestVersionText: String {
        if model.updateChecking { return L.t("检查中…") }
        switch model.update.state {
        case .idle:
            return "—"
        case .available:
            return model.updateSkipped
                ? L.t("%@（已跳过）", model.update.latest)
                : model.update.latest
        case .upToDate:
            return model.update.latest.isEmpty ? Brand.version : model.update.latest
        case .failed:
            return model.update.error ?? L.t("检查失败")
        }
    }

    private var updateTintText: String? {
        if model.updateChecking { return L.t("检查中…") }
        switch model.update.state {
        case .available: return model.updateSkipped ? L.t("已跳过") : L.t("有可用更新")
        case .upToDate: return L.t("已是最新")
        case .failed: return L.t("检查失败")
        case .idle: return nil
        }
    }

    /// GitHub 的 `published_at` 是 ISO8601，取到分钟就够
    private func shortDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        return TimeText.stamp(date)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: L.t("关于"), trailing: nil)
            VStack(spacing: 0) {
                KeyValueRow(label: L.t("应用"), value: "ServDock 启服", mono: true)
                divider
                KeyValueRow(label: L.t("版本"), value: appVersion, mono: true)
                divider
                KeyValueRow(label: "Homebrew", value: model.brewVersionText.isEmpty ? "—" : model.brewVersionText, mono: true)
                divider
                KeyValueRow(label: L.t("服务数量"), value: L.t("%d 个已安装 / %d 个内置", model.installedItems().count, ServiceSpec.catalog.count))
                divider
                KeyValueRow(
                    label: L.t("刷新频率"),
                    value: L.t("%d 秒（后台 %d 秒）", Int(model.pollInterval), Int(AppModel.backgroundInterval))
                )
                divider
                KeyValueRow(label: L.t("easytier-cli"), value: model.easyTier.cliPath.map(shortPath) ?? L.t("未安装"), mono: true)
                divider
                KeyValueRow(label: "mise", value: model.mise.version.isEmpty ? L.t("未安装") : model.mise.version, mono: true)
                divider
                KeyValueRow(label: L.t("数据目录"), value: shortPath(Brand.supportDir), mono: true, copyable: true) {
                    model.copyToPasteboard(Brand.supportDir, label: L.t("数据目录"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .cardSurface()

            HStack(spacing: 6) {
                PillButton(title: L.t("在 Finder 中打开数据目录"), systemImage: "folder", compact: true) {
                    model.reveal(Brand.supportDir)
                }
                PillButton(title: L.t("诊断信息"), systemImage: "stethoscope", compact: true) {
                    model.openInTerminal(diagnosticsCommand)
                }
            }
            .padding(.top, 2)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.border.opacity(0.55)).frame(height: 1)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var diagnosticsCommand: String {
        let bin = Bundle.main.executablePath ?? "ServDock"
        return Shell.quote(bin) + " --probe"
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(of: Shell.home, with: "~")
    }
}
