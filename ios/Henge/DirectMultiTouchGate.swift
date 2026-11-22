import Foundation

/// A stationary multifinger tap in Direct Touch is never a guest trackpad tap.
/// Forward native scroll/Spaces gestures only after actual movement begins.
struct DirectMultiTouchGate {
    private var started: TimeInterval?
    private var mostFingers = 0
    private(set) var forwarding = false
    mutating func begin(count: Int, time: TimeInterval) {
        if started == nil { started = time }
        mostFingers = max(mostFingers, count)
    }
    mutating func move(distance: Double, count: Int) -> Bool {
        guard !forwarding, distance.isFinite, distance >= 8,
              mostFingers < 2 || count >= 2 else { return false }
        forwarding = true
        return true
    }
    func reveal(time: TimeInterval) -> Bool {
        guard let started else { return false }
        return !forwarding && mostFingers >= 4 && time >= started && time - started < 0.6
    }
    mutating func reset() { self = Self() }
}
