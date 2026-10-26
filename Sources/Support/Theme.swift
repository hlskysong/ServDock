import AppKit
import SwiftUI

/// 自适应配色（浅色 / 深色）
enum Theme {
    static let page = dynamic(light: 0xF4F5F7, dark: 0x111317)
    static let sidebar = dynamic(light: 0xEBEDF1, dark: 0x0F1013)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1F222A)
    static let cardHover = dynamic(light: 0xFAFBFD, dark: 0x262A33)
    static let cardSoft = dynamic(light: 0xF7F8FA, dark: 0x171920)
    static let border = dynamic(light: 0xE1E4EA, dark: 0x30343E)
    static let borderStrong = dynamic(light: 0xD2D7DF, dark: 0x3A3F4A)
    static let textPrimary = dynamic(light: 0x171A20, dark: 0xF2F3F6)
    static let textSecondary = dynamic(light: 0x646C7A, dark: 0x9BA3B0)
    static let textTertiary = dynamic(light: 0x98A0AD, dark: 0x6E7683)
    static let selection = dynamic(light: 0xE2E6F5, dark: 0x272B3A)

    static let accent = dynamic(light: 0x4F63E8, dark: 0x7C8CFF)
    static let green = dynamic(light: 0x16A34A, dark: 0x3DDC84)
    static let red = dynamic(light: 0xDC2626, dark: 0xF87171)
    static let amber = dynamic(light: 0xD97706, dark: 0xFBBF24)
    static let blue = dynamic(light: 0x2563EB, dark: 0x60A5FA)
    static let purple = dynamic(light: 0x7C3AED, dark: 0xA78BFA)
    static let teal = dynamic(light: 0x0D9488, dark: 0x2DD4BF)
    static let pink = dynamic(light: 0xDB2777, dark: 0xF472B6)
    static let slate = dynamic(light: 0x64748B, dark: 0x94A3B8)
    static let cyan = dynamic(light: 0x0891B2, dark: 0x22D3EE)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(srgbHex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(srgbHex hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(srgbHex: hex))
    }
}

enum Metrics {
    static let cardRadius: CGFloat = 14
    static let sidebarWidth: CGFloat = 234
    static let pagePadding: CGFloat = 22
}

extension View {
    /// 卡片容器样式
    func cardSurface(hovering: Bool = false, radius: CGFloat = Metrics.cardRadius) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(hovering ? Theme.cardHover : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(hovering ? 0.07 : 0.04), radius: hovering ? 10 : 5, x: 0, y: 2)
    }
}
