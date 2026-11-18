import Foundation

/// Keep the saved mode compatible with earlier builds, but never turn display
/// cursor feedback into relative mouse commands. PVG cursor updates have no
/// acknowledgement or sequence number and cannot safely position a HID mouse.
enum TouchInputSafety {
    static let reset = Notification.Name("henge.input.reset")
    static let fallbackDescription = "Direct Touch currently uses Trackpad controls for reliable input. Swipe to move the pointer, tap to click, or hold then move to drag windows, icons or select text. Two fingers scroll or right-click."
}
