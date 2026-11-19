import Foundation

/// USB HID units. Keep controller pairing and device identifiers on iPadOS.
struct GamepadSample {
    let buttons: UInt16
    let hat: Int32
    let axes: [Int32]

    init(buttons: UInt16, dpadX: Float, dpadY: Float, leftX: Float = 0, leftY: Float = 0,
         rightX: Float = 0, rightY: Float = 0, leftTrigger: Float = 0, rightTrigger: Float = 0) {
        self.buttons = buttons
        func direction(_ v: Float) -> Int { v.isFinite ? (v > 0.5 ? 1 : v < -0.5 ? -1 : 0) : 0 }
        switch (direction(dpadX), direction(dpadY)) {
        case (0, 1): hat = 0
        case (1, 1): hat = 1
        case (1, 0): hat = 2
        case (1, -1): hat = 3
        case (0, -1): hat = 4
        case (-1, -1): hat = 5
        case (-1, 0): hat = 6
        case (-1, 1): hat = 7
        default: hat = 8
        }
        func stick(_ value: Float) -> Int32 {
            guard value.isFinite else { return 0 }
            let magnitude = min(abs(value), 1)
            guard magnitude > 0.06 else { return 0 }
            return Int32(((magnitude - 0.06) / 0.94 * 32767 * (value < 0 ? -1 : 1)).rounded())
        }
        func trigger(_ value: Float) -> Int32 {
            guard value.isFinite, value > 0.01 else { return 0 }
            return Int32((min(value, 1) * 32767).rounded())
        }
        axes = [stick(leftX), -stick(leftY), stick(rightX), -stick(rightY), trigger(leftTrigger), trigger(rightTrigger)]
    }
}
