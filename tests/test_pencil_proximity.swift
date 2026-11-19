import Foundation

@main struct PencilProximityTests {
    static func main() {
        var state = PencilProximity()
        precondition(state.hoverChanged() && state.isHovering)
        state.beginContact()
        precondition(!state.hoverEnded(), "hover ending at tip-down cannot release a stroke")
        precondition(!state.hoverChanged(), "hover cannot reposition an active stroke")
        state.recordSample(estimate: 4, timestamp: 1)
        precondition(state.acceptsCorrection(estimate: 4, timestamp: 1))
        state.recordSample(estimate: 5, timestamp: 2)
        precondition(!state.acceptsCorrection(estimate: 4, timestamp: 1), "old pressure must not move the tip backwards")
        precondition(!state.acceptsCorrection(estimate: nil, timestamp: 2))
        let lifted = state.endContact()
        precondition(!state.hoverEnded(), "late hover-end cannot cancel the queued tip-up")
        precondition(!state.acceptsCorrection(estimate: 5, timestamp: 2), "late updates cannot restart contact")
        precondition(state.hoverChanged())
        precondition(!state.expire(lifted), "resumed hover invalidates the delayed leave")
        precondition(state.hoverEnded() && !state.hoverEnded())
        state.beginContact()
        let old = state.endContact()
        state.beginContact()
        precondition(!state.expire(old), "an old timeout cannot release a new stroke")
        let current = state.endContact()
        precondition(state.expire(current) && !state.expire(current))
        state.beginContact()
        let cancelled = state.endContact()
        state.reset()
        precondition(!state.expire(cancelled), "mode/background resets invalidate callbacks")
        print("PASS: Pencil hover/contact ordering, correction freshness and delayed-leave lifetime")
    }
}
