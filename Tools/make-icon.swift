// 生成 AppIcon.icns：swiftc Tools/make-icon.swift -o /tmp/mkicon && /tmp/mkicon
// 视觉：靛蓝→紫渐变圆角底 + 三行「服务条」+ 运行状态点

import AppKit
import Foundation

let canvas: CGFloat = 1024
let iconsetDir = "/tmp/servicedock.iconset"

func makeIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // 圆角底（macOS 图标留白约 64pt）
    let inset: CGFloat = 62
    let rect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let radius: CGFloat = 196
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.addPath(path)
    context.clip()

    let colors = [
        NSColor(srgbRed: 0.33, green: 0.40, blue: 0.95, alpha: 1).cgColor,
        NSColor(srgbRed: 0.55, green: 0.28, blue: 0.92, alpha: 1).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    // 顶部高光
    let highlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(white: 1, alpha: 0.22).cgColor,
            NSColor(white: 1, alpha: 0.0).cgColor
        ] as CFArray,
        locations: [0, 1]
    )
    if let highlight {
        context.drawLinearGradient(
            highlight,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.midY),
            options: []
        )
    }
    context.restoreGState()

    // 三行服务条
    let barWidths: [CGFloat] = [486, 406, 446]
    let barHeight: CGFloat = 92
    let startY: CGFloat = 300
    let gap: CGFloat = 60
    let barX: CGFloat = 268

    for index in 0..<3 {
        let alpha: CGFloat = index == 0 ? 0.97 : 0.80
        let y = startY + CGFloat(2 - index) * (barHeight + gap)
        let width = barWidths[index]
        let barRect = CGRect(x: barX, y: y, width: width, height: barHeight)
        let barPath = CGPath(
            roundedRect: barRect,
            cornerWidth: barHeight / 2,
            cornerHeight: barHeight / 2,
            transform: nil
        )
        context.setFillColor(NSColor(white: 1, alpha: alpha).cgColor)
        context.addPath(barPath)
        context.fillPath()

        // 状态点
        let dotSize: CGFloat = 34
        let dotX = barX + 46
        let dotY = y + (barHeight - dotSize) / 2
        let dotColor: NSColor
        switch index {
        case 0: dotColor = NSColor(srgbRed: 0.13, green: 0.78, blue: 0.47, alpha: 1)
        case 1: dotColor = NSColor(srgbRed: 0.36, green: 0.42, blue: 0.95, alpha: 1)
        default: dotColor = NSColor(srgbRed: 0.55, green: 0.28, blue: 0.92, alpha: 1)
        }
        context.setFillColor(dotColor.cgColor)
        context.fillEllipse(in: CGRect(x: dotX, y: dotY, width: dotSize, height: dotSize))

        // 右侧三条短横线（模拟文本行）
        let linesX = dotX + dotSize + 34
        let lineYs = [y + 28, y + 48]
        for (lineIndex, lineY) in lineYs.enumerated() {
            let lineWidth: CGFloat = lineIndex == 0 ? 150 : 96
            context.setFillColor(NSColor(white: 0.45, alpha: 0.35).cgColor)
            let lineRect = CGRect(x: linesX, y: lineY, width: lineWidth, height: 16)
            context.addPath(CGPath(roundedRect: lineRect, cornerWidth: 8, cornerHeight: 8, transform: nil))
            context.fillPath()
        }
    }

    image.unlockFocus()
    return image
}

let master = makeIcon()
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    for scale in 1...2 {
        let pixels = size * scale
        if pixels > 1024 { continue }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { continue }
        rep.size = NSSize(width: pixels, height: pixels)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { continue }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(size)x\(size)\(suffix).png"
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: iconsetDir + "/" + name))
        }
    }
}
print("iconset -> \(iconsetDir)")
