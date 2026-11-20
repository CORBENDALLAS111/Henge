import Foundation
import CoreGraphics

/// Convert a classified swipe to two synchronized Magic Trackpad contacts.
/// macOS owns acceleration/inertia: no wheel quantization or second momentum tail.
struct OneFingerScroll {
    enum Event: Equatable {
        case touch(Int32, phase: Int32, x: Int32, y: Int32, time: UInt32)
        case frame(UInt32)
    }
    private enum Axis { case vertical, horizontal }
    private var origin = CGPoint.zero
    private var scale: CGFloat = 1
    private var center = CGPoint.zero
    private var last = CGPoint.zero
    private var lastTime: TimeInterval = 0
    private var axis: Axis?
    private(set) var active = false
    private static let width: CGFloat = 8134, height: CGFloat = 5206, halfSpacing: CGFloat = 100

    private static func stamp(_ time: TimeInterval) -> UInt32 {
        UInt32(truncatingIfNeeded: Int64((time * 1000).rounded(.down)))
    }
    private static func valid(_ point: CGPoint, time: TimeInterval) -> Bool {
        point.x.isFinite && point.y.isFinite && abs(point.x) < 1e9 && abs(point.y) < 1e9 && time.isFinite && time >= 0 && time < 1e12
    }
    private func contacts(_ point: CGPoint, phase: Int32, time: TimeInterval) -> [Event] {
        let x = min(max(point.x, Self.halfSpacing), Self.width - Self.halfSpacing)
        let y = min(max(point.y, 0), Self.height)
        return [
            .touch(8, phase: phase, x: Int32((x - Self.halfSpacing).rounded()), y: Int32(y.rounded()), time: Self.stamp(time)),
            .touch(9, phase: phase, x: Int32((x + Self.halfSpacing).rounded()), y: Int32(y.rounded()), time: Self.stamp(time))
        ]
    }
    mutating func begin(_ point: CGPoint, size: CGSize, time: TimeInterval) -> [Event] {
        guard Self.valid(point, time: time), size.width.isFinite, size.height.isFinite,
              size.width >= 1, size.height >= 1, size.width <= 100_000, size.height <= 100_000 else { return end(time: time) }
        let releases = end(time: time)
        origin = point
        scale = min(Self.width / size.width, Self.height / size.height)
        center = CGPoint(x: Self.width / 2 + (point.x - size.width / 2) * scale,
                         y: Self.height / 2 + (point.y - size.height / 2) * scale)
        last = center; lastTime = time; axis = nil; active = true
        // Contact-down queues native frames; subsequent moves commit both together.
        return releases + contacts(center, phase: 0, time: time)
    }
    mutating func move(_ point: CGPoint, time: TimeInterval) -> [Event] {
        guard active, Self.valid(point, time: time), time > lastTime else { return [] }
        let dx = point.x - origin.x, dy = point.y - origin.y
        if axis == nil && dx == 0 && dy == 0 { return [] }
        if axis == nil { axis = abs(dx) > abs(dy) * 1.25 ? .horizontal : .vertical }
        let point = CGPoint(x: center.x + (axis == .horizontal ? dx * scale : 0),
                            y: center.y + (axis == .vertical ? dy * scale : 0))
        lastTime = time
        guard point != last else { return [] }
        last = point
        return contacts(last, phase: 1, time: time) + [.frame(Self.stamp(time))]
    }
    mutating func end(time: TimeInterval) -> [Event] {
        guard active else { return [] }
        active = false; axis = nil
        let at = time.isFinite && time >= lastTime && time < 1e12 ? time : lastTime
        return contacts(last, phase: 2, time: at)
    }
}
