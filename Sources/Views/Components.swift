import SwiftUI

// MARK: - 服务图标

enum ServiceGlyph {
    static func symbol(for id: String) -> String {
        switch id {
        case "redis": return "bolt.horizontal.circle.fill"
        case "valkey": return "bolt.circle.fill"
        case "mysql": return "tablecells.fill"
        case "mysql@8.4": return "tablecells.fill"
        case "mariadb": return "tablecells.badge.ellipsis"
        case "postgresql@16", "postgresql@17": return "cylinder.fill"
        case "mongodb-community", "mongodb-community@8.0", "mongodb-community@7.0": return "leaf.fill"
        case "nginx": return "server.rack"
        case "httpd": return "network"
        case "caddy": return "lock.shield.fill"
        case "zookeeper": return "point.3.connected.trianglepath.dotted"
        case "kafka": return "arrow.triangle.branch"
        case "rabbitmq": return "tray.full.fill"
        case "etcd": return "circle.grid.cross.fill"
        case "elasticsearch": return "magnifyingglass"
        case "meilisearch": return "sparkle.magnifyingglass"
        case "memcached": return "memorychip.fill"
        case "minio": return "externaldrive.connected.to.line.below"
        case "rustfs": return "archivebox.fill"
        case "easytier": return "globe.asia.australia.fill"
        default: return "shippingbox.fill"
        }
    }
}

// MARK: - 图标底座

struct IconBadge: View {
    let symbol: String
    var tint: Color
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(tint.opacity(0.13))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .strokeBorder(tint.opacity(0.16), lineWidth: 1)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
    }
}

// MARK: - 状态胶囊

struct StatusPill: View {
    var status: BrewStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(status.color.opacity(0.3), lineWidth: 4)
                        .scaleEffect(status.isActive ? 1.0 : 0.001)
                )
            Text(status.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(status.color.opacity(0.12)))
    }
}

// MARK: - 按钮

struct PillButton: View {
    enum Kind { case primary, secondary, ghost, danger }

    var title: String
    var systemImage: String?
    var tint: Color = Theme.accent
    var kind: Kind = .secondary
    var compact = false
    var loading = false
    var enabled = true
    var help: String?
    var action: () -> Void

    @State private var hovering = false

    private var foreground: Color {
        if !enabled { return Theme.textTertiary }
        switch kind {
        case .primary: return .white
        case .secondary: return Theme.textPrimary
        case .ghost: return tint
        case .danger: return Theme.red
        }
    }

    private var background: Color {
        if !enabled { return Theme.card }
        switch kind {
        case .primary: return tint.opacity(hovering ? 1.0 : 0.92)
        case .secondary: return hovering ? Theme.cardSoft : Theme.card
        case .ghost: return tint.opacity(hovering ? 0.16 : 0.10)
        case .danger: return Theme.red.opacity(hovering ? 0.14 : 0.08)
        }
    }

    private var borderColor: Color {
        if !enabled { return Theme.borderStrong }
        switch kind {
        case .primary: return .clear
        case .secondary: return hovering ? Theme.borderStrong : Theme.border
        case .ghost: return .clear
        case .danger: return Theme.red.opacity(0.25)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if loading {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.62)
                        .frame(width: 10, height: 10)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
                }
                Text(L.t(title))
                    .font(.system(size: compact ? 11 : 12, weight: .medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 5.5)
            .background(
                Capsule(style: .continuous).fill(background)
            )
            .overlay(
                Capsule(style: .continuous).strokeBorder(borderColor, lineWidth: 1)
            )
            .opacity(enabled ? 1 : 0.9)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // 不用 .disabled 控制可用态：SwiftUI 会再叠一层自动调暗，把禁用配色压得看不见
        .disabled(loading)
        .allowsHitTesting(enabled && !loading)
        .onHover { hovering = $0 && enabled }
        .help(L.t(help ?? title))
    }
}

/// 顶部统计卡（概览 / 定时任务共用同一尺寸，避免两边各写一份慢慢走偏）
struct MetricPill: View {
    var label: String
    var value: String
    var tint: Color
    var symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 17)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minWidth: 122, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// 纯图标圆形按钮
struct IconButton: View {
    var systemImage: String
    var tint: Color = Theme.textSecondary
    var size: CGFloat = 26
    var help: String?
    /// 转圈：把「正在刷新」画在按钮上，不额外占位，也不改动任何布局
    var spinning: Bool = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(hovering ? tint : Theme.textSecondary)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                // 停下时不给动画，直接归位；否则会从 360° 反向转回 0°，看着像卡了一下
                .animation(spinning ? .linear(duration: 1.1).repeatForever(autoreverses: false) : nil,
                           value: spinning)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(hovering ? tint.opacity(0.12) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L.t(help ?? ""))
    }
}

// MARK: - 信息行

struct KeyValueRow: View {
    var label: String
    var value: String
    var mono = false
    var copyable = false
    var onCopy: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(L.t(label))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .lineLimit(hovering ? 4 : 2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if copyable, hovering {
                IconButton(systemImage: "doc.on.doc", size: 20, help: "复制") {
                    onCopy?()
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .onHover { hovering = $0 }
    }
}

/// 小标签
struct TagChip: View {
    var text: String
    var tint: Color = Theme.textSecondary

    var body: some View {
        Text(L.t(text))
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(L.t(title))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(L.t(message))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                PillButton(title: actionTitle, systemImage: "arrow.down.circle", kind: .primary, action: action)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

// MARK: - Toast

struct ToastView: View {
    var toast: ToastMessage

    private var tint: Color {
        switch toast.kind {
        case .success: return Theme.green
        case .error: return Theme.red
        case .info: return Theme.blue
        }
    }

    private var symbol: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(toast.text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: 520, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.card)
                .shadow(color: .black.opacity(0.16), radius: 14, y: 4)
        )
        .overlay(
            Capsule(style: .continuous).strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

// MARK: - 分组标题

struct SectionLabel: View {
    var text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L.t(text))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

// MARK: - 搜索框

struct SearchField: View {
    @Binding var text: String
    var placeholder = "搜索服务"

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField(L.t(placeholder), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .frame(width: 118)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Theme.card)
        )
        .overlay(
            Capsule().strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}
