import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Convert a classified swipe to two synchronized Magic Trackpad contacts.
/// macOS owns acceleration/inertia: no wheel quantization or second momentum tail.
struct OneFingerScroll {
    enum Event: Equatable {
        case touch(Int32, phase: Int32, x: Int32, y: Int32, time: UInt32)
        case frame(UInt32)
    }
    private enum Axis { case vertical, horizontal, both }
    private var origin = CGPoint.zero
    private var scale: CGFloat = 1
    private var center = CGPoint.zero
    private var last = CGPoint.zero
    private var lastView = CGPoint.zero
    private var lastTime: TimeInterval = 0
    private var lastMotionTime: TimeInterval = 0
    private var settled = false
    private var axis: Axis?
    private(set) var active = false
    private static let width: CGFloat = 8134, height: CGFloat = 5206, halfSpacing: CGFloat = 100

    private static func stamp(_ time: TimeInterval) -> UInt32 {
        UInt32(truncatingIfNeeded: Int64((time * 1000).rounded(.down)))
    }
    private static func valid(_ point: CGPoint, time: TimeInterval) -> Bool {
        point.x.isFinite && point.y.isFinite && abs(point.x) < 1e9 && abs(point.y) < 1e9 && time.isFinite && time >= 0 && time < 1e12
    }
    private static func bounded(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, halfSpacing), width - halfSpacing).rounded(),
                y: min(max(point.y, 0), height).rounded())
    }
    private func contacts(_ point: CGPoint, phase: Int32, time: TimeInterval) -> [Event] {
        let p = Self.bounded(point), x = p.x, y = p.y
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
        center = Self.bounded(CGPoint(x: Self.width / 2 + (point.x - size.width / 2) * scale,
                                     y: Self.height / 2 + (point.y - size.height / 2) * scale))
        last = center; lastView = point; lastTime = time; lastMotionTime = time
        settled = false; axis = nil; active = true
        // Contact-down queues native frames; subsequent moves commit both together.
        return releases + contacts(center, phase: 0, time: time)
    }
    mutating func move(_ point: CGPoint, time: TimeInterval) -> [Event] {
        guard active, Self.valid(point, time: time), time > lastTime else { return [] }
        let dx = point.x - origin.x, dy = point.y - origin.y
        if axis == nil && dx == 0 && dy == 0 { return [] }
        if axis == nil {
            axis = abs(dx) > abs(dy) * 1.25 ? .horizontal
                : abs(dy) > abs(dx) * 1.25 ? .vertical : .both
        }
        // Integrate from the last physical sample, discarding travel beyond the
        // sensor edge. Reversing direction then responds immediately, rather
        // than requiring the finger to cross an invisible offscreen dead zone.
        center = CGPoint(x: min(max(center.x + (axis == .vertical ? 0 : (point.x - lastView.x) * scale), Self.halfSpacing), Self.width - Self.halfSpacing),
                         y: min(max(center.y + (axis == .horizontal ? 0 : (point.y - lastView.y) * scale), 0), Self.height))
        lastView = point
        lastTime = time
        let next = Self.bounded(center)
        guard next != last else { return settle(time: time) }
        last = next; lastMotionTime = time; settled = false
        return contacts(last, phase: 1, time: time) + [.frame(Self.stamp(time))]
    }
    private mutating func settle(time: TimeInterval) -> [Event] {
        // The guest estimates release velocity from recent reports. A swipe
        // followed by a pause must not fling using its old moving sample.
        guard !settled, time - lastMotionTime >= 0.05 else { return [] }
        settled = true
        return contacts(last, phase: 1, time: time) + [.frame(Self.stamp(time))]
    }
    mutating func end(time: TimeInterval) -> [Event] {
        guard active else { return [] }
        active = false; axis = nil
        let at = time.isFinite && time >= lastTime && time < 1e12 ? time : lastTime
        return settle(time: at) + contacts(last, phase: 2, time: at)
    }
}
