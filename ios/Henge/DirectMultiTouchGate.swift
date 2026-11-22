import Foundation

/// A stationary multifinger tap in Direct Touch is never a guest trackpad tap.
/// An explicitly enabled two-finger context tap uses an absolute mouse click.
/// Forward native scroll/Spaces gestures only after actual movement begins.
struct DirectMultiTouchGate {
    static let contextTapKey = "henge.touch.twoFingerContextTap"
    private var started: TimeInterval?
    private var mostFingers = 0
    private var distance = 0.0
    private(set) var forwarding = false
    mutating func begin(count: Int, time: TimeInterval) {
        if started == nil { started = time }
        mostFingers = max(mostFingers, count)
    }
    mutating func move(distance: Double, count: Int) -> Bool {
        record(distance: distance)
        guard !forwarding, distance.isFinite, distance >= 8,
              mostFingers < 2 || count >= 2 else { return false }
        forwarding = true
        return true
    }
    func reveal(time: TimeInterval) -> Bool {
        guard let started else { return false }
        return !forwarding && distance < 8 && mostFingers >= 4 && time >= started && time - started < 0.6
    }
    mutating func record(distance: Double) {
        self.distance = distance.isFinite ? max(self.distance, abs(distance)) : .infinity
    }
    func secondaryTap(time: TimeInterval) -> Bool {
        guard let started, started.isFinite, time.isFinite else { return false }
        return !forwarding && mostFingers == 2 && distance < 8 && time >= started && time - started <= 0.3
    }
    mutating func reset() { self = Self() }
}
