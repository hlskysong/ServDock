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
