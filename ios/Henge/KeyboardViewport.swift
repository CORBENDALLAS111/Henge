import Foundation
import CoreGraphics

enum SessionKeyboard {
    static let modeKey = "henge.keyboard.autoMode"
    static let keepSizeKey = "henge.keyboard.keepSize"
    static let directTap = Notification.Name("henge.input.directTap")
}

/// Translate without changing scale or horizontal placement.
enum KeyboardViewport {
    static func frame(_ base: CGRect, keyboard: CGRect, focus: CGPoint, pan: CGFloat) -> CGRect {
        guard !keyboard.isEmpty, keyboard.minY.isFinite, base.width > 0, base.height > 0 else { return base }
        let bottom = max(keyboard.minY - 58, 44)
        let y = focus.y.isFinite ? min(max(focus.y, 0), 1) : 0.5
        let low = min(base.minY, bottom - base.height)
        let high = max(base.minY, 0)
        let automatic = min(base.minY, bottom - y * base.height - 12)
        let offset = pan.isFinite ? pan : 0
        return CGRect(x: base.minX, y: min(high, max(low, automatic + offset)), width: base.width, height: base.height)
    }
}
