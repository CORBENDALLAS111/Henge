import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

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

/// One classified click. Its viewport change must wait for guest delivery.
struct KeyboardTapRequest {
    let point: CGPoint
    let began: TimeInterval
    enum Decision: Equatable { case wait, discard, apply(CGPoint, open: Bool) }
    func resolve(now: TimeInterval, inputActive: Bool, penIdle: Bool, mode: String,
                 keyboardVisible: Bool, focusStatus: Int32, focusAge: Double, focusBounds: CGRect,
                 targetEditable: Bool? = nil) -> Decision {
        let elapsed = now - began
        guard inputActive, elapsed >= 0, elapsed <= 2, point.x.isFinite, point.y.isFinite else { return .discard }
        guard elapsed >= 0.18, penIdle else { return .wait }
        if mode == "text", targetEditable == false {
            return .discard // keep an already visible keyboard and its viewport steady
        }
        let open = mode == "tap" || (mode == "text" && focusStatus == 1 && !focusBounds.isEmpty && focusBounds.contains(point) && focusAge >= 0 && focusAge < elapsed - 0.15)
        if open || keyboardVisible || (mode != "tap" && mode != "text") { return .apply(point, open: open) }
        return .wait
    }
}
