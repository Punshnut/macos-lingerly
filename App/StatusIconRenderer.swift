import AppKit

/// Draws the menu bar icon for each app state.
enum StatusIconRenderer {
    /// Returns a template image rendered for the current status display and pulse.
    static func image(
        nextDisplay: AppStateController.NextBreakDisplay,
        pulse: CGFloat
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        let center = CGPoint(x: rect.midX, y: rect.midY)

        let baseAlpha: CGFloat = {
            if case .breakActive = nextDisplay {
                return 0.78 + 0.08 * pulse
            }
            return 0.88
        }()

        let color = NSColor.labelColor.withAlphaComponent(baseAlpha)
        color.set()

        switch nextDisplay {
        case .inactive:
            drawPause(at: center, barHeight: 8.0, barWidth: 2.2)

        case .running:
            drawPlay(at: center, width: 8.0, height: 8.8)

        case .paused:
            drawPause(at: center, barHeight: 8.0, barWidth: 2.2)

        case .muted:
            drawMuted(at: center)

        case .cooldown:
            drawPause(at: center, barHeight: 8.0, barWidth: 2.2)

        case .snoozing:
            drawRing(at: center, radius: 5.0, lineWidth: 1.3)

        case .breakDue:
            drawRing(at: center, radius: 5.0, lineWidth: 1.3)

        case .breakActive:
            drawRing(at: center, radius: 5.0, lineWidth: 1.5)
        }

        image.isTemplate = true
        return image
    }

    private static func drawMuted(at center: CGPoint) {
        drawRing(at: center, radius: 5.0, lineWidth: 1.3)
        let slash = NSBezierPath()
        slash.lineWidth = 1.4
        slash.lineCapStyle = .round
        slash.move(to: CGPoint(x: center.x - 3.0, y: center.y + 3.0))
        slash.line(to: CGPoint(x: center.x + 3.0, y: center.y - 3.0))
        slash.stroke()
    }

    private static func drawRing(at center: CGPoint, radius: CGFloat, lineWidth: CGFloat) {
        let ringRect = NSRect(
            x: center.x - radius,
            y: center.y - radius + 0.5,
            width: radius * 2,
            height: radius * 2
        )
        let ring = NSBezierPath(ovalIn: ringRect)
        ring.lineWidth = lineWidth
        ring.stroke()
    }

    private static func drawPause(at center: CGPoint, barHeight: CGFloat, barWidth: CGFloat) {
        let barCorner: CGFloat = 0.7
        let barOffset: CGFloat = 3.0
        let barY = center.y - (barHeight / 2) + 0.5
        let leftBar = NSRect(
            x: center.x - barOffset - (barWidth / 2),
            y: barY,
            width: barWidth,
            height: barHeight
        )
        let rightBar = NSRect(
            x: center.x + barOffset - (barWidth / 2),
            y: barY,
            width: barWidth,
            height: barHeight
        )
        NSBezierPath(roundedRect: leftBar, xRadius: barCorner, yRadius: barCorner).fill()
        NSBezierPath(roundedRect: rightBar, xRadius: barCorner, yRadius: barCorner).fill()
    }

    private static func drawPlay(at center: CGPoint, width: CGFloat, height: CGFloat) {
        let halfHeight = height / 2
        let path = NSBezierPath()
        path.move(to: CGPoint(x: center.x - width / 2, y: center.y - halfHeight + 0.5))
        path.line(to: CGPoint(x: center.x + width / 2, y: center.y + 0.5))
        path.line(to: CGPoint(x: center.x - width / 2, y: center.y + halfHeight + 0.5))
        path.close()
        path.fill()
    }
}
