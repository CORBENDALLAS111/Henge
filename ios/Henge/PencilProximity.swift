import Foundation

/// UIKit can end hover when the tip touches the screen, and resume hover after
/// tip-up. Those notifications must never cancel queued contact/button edges.
struct PencilProximity {
    private enum Phase: Equatable { case idle, hover, contact, awaitingHover }
    private var phase = Phase.idle
    private var generation: UInt64 = 0
    private var latestEstimate: Int?
    private var latestTimestamp: TimeInterval = 0

    var isHovering: Bool { phase == .hover }

    mutating func reset() {
        generation &+= 1
        phase = .idle
        latestEstimate = nil
        latestTimestamp = 0
    }

    mutating func beginContact() {
        reset()
        phase = .contact
    }

    mutating func recordSample(estimate: Int?, timestamp: TimeInterval) {
        guard phase == .contact else { return }
        latestEstimate = estimate
        latestTimestamp = timestamp
    }

    func acceptsCorrection(estimate: Int?, timestamp: TimeInterval) -> Bool {
        phase == .contact && estimate != nil && estimate == latestEstimate && timestamp == latestTimestamp
    }

    mutating func endContact() -> UInt64 {
        generation &+= 1
        phase = .awaitingHover
        latestEstimate = nil
        return generation
    }

    mutating func hoverChanged() -> Bool {
        guard phase != .contact else { return false }
        generation &+= 1
        phase = .hover
        return true
    }

    mutating func hoverEnded() -> Bool {
        guard phase == .hover else { return false }
        reset()
        return true
    }

    /// A delayed proximity leave belongs only to that particular lifted stroke.
    mutating func expire(_ token: UInt64) -> Bool {
        guard generation == token, phase == .awaitingHover else { return false }
        reset()
        return true
    }
}
