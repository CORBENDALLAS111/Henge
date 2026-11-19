import Foundation
import CoreGraphics

/// Standard HID units; independent of guest resolution and mouse acceleration.
struct AbsolutePenSample {
    let x: Int32, y: Int32, pressure: Int32, tiltX: Int32, tiltY: Int32, twist: Int32, flags: Int32

    init(point: CGPoint, size: CGSize, pressure: CGFloat, altitude: CGFloat = .pi / 2,
         azimuth: CGFloat = 0, roll: CGFloat = 0, flags: Int32) {
        func units(_ value: CGFloat, max: CGFloat) -> Int32 {
            guard value.isFinite else { return 0 }
            return Int32((min(Swift.max(value, 0), 1) * max).rounded())
        }
        x = units(point.x / Swift.max(size.width, 1), max: 32767)
        y = units(point.y / Swift.max(size.height, 1), max: 32767)
        self.flags = flags
        self.pressure = flags & 1 == 0 ? 0 : Swift.max(1, units(pressure, max: 4095))
        let a = altitude.isFinite ? min(Swift.max(altitude, 0), .pi / 2) : .pi / 2
        let z = azimuth.isFinite ? azimuth : 0
        func tilt(_ horizontal: CGFloat) -> Int32 {
            Int32((atan2(horizontal, sin(a)) * 18000 / .pi).rounded())
        }
        tiltX = tilt(cos(a) * cos(z))
        tiltY = tilt(cos(a) * sin(z))
        let turn = roll.isFinite ? (roll.truncatingRemainder(dividingBy: 2 * .pi) + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi) : 0
        twist = min(35999, Int32((turn * 18000 / .pi).rounded()))
    }
}
