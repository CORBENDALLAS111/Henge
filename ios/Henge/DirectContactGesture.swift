import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Desktop gesture classification in view points, before any guest button-down.
/// A held Pencil produces a double-click only on lift, so it can still become a drag.
struct DirectContactGesture {
    enum Tool { case finger, pencil }
    enum Action: Equatable {
        case down(CGPoint), move(CGPoint), up(CGPoint)
        case click(CGPoint, count: Int, secondary: Bool)
        case scrollBegin(CGPoint, time: TimeInterval)
        case scroll(CGPoint, time: TimeInterval)
        case scrollEnd(time: TimeInterval)
    }
    private enum Phase { case idle, pending, dragging, scrolling, consumed }
    private var phase = Phase.idle
    private var tool = Tool.finger
    private var origin = CGPoint.zero
    private var began: TimeInterval = 0
    private var scrollSwipes = false
    static let scrollKey = "henge.touch.oneFingerScrolling"
    static let defaultOneFingerScrolling = true
    static let dragDelay: TimeInterval = 0.22
    static let contextDelay: TimeInterval = 0.55
    static let pencilDoubleDelay: TimeInterval = 0.45

    mutating func begin(_ point: CGPoint, tool: Tool, time: TimeInterval, scrollFingerSwipes: Bool = false) {
        self.tool = tool; origin = point; began = time; phase = .pending
        scrollSwipes = scrollFingerSwipes && tool == .finger
    }
    mutating func move(_ point: CGPoint, time: TimeInterval? = nil) -> [Action] {
        guard point.x.isFinite, point.y.isFinite else { return [] }
        if let time, !time.isFinite || time < began { return [] }
        switch phase {
        case .pending:
            let distance = hypot(point.x - origin.x, point.y - origin.y)
            guard distance >= (tool == .finger ? 10 : 4) else { return [] }
            if scrollSwipes, let time, time.isFinite, time >= began, time - began < Self.dragDelay {
                phase = .scrolling
                return [.scrollBegin(origin, time: began), .scroll(point, time: time)]
            }
            phase = .dragging
            return [.down(origin), .move(point)]
        case .dragging: return [.move(point)]
        case .scrolling: return [.scroll(point, time: time ?? began)]
        default: return []
        }
    }
    mutating func hold(time: TimeInterval) -> [Action] {
        guard phase == .pending, tool == .finger, time - began >= Self.contextDelay else { return [] }
        phase = .consumed
        return [.click(origin, count: 1, secondary: true)]
    }
    mutating func end(_ point: CGPoint, time: TimeInterval) -> [Action] {
        defer { phase = .idle }
        switch phase {
        case .pending:
            // A flick can end before UIKit supplies a move sample. It is not a
            // stationary tap and must not click or auto-open the keyboard.
            guard hypot(point.x - origin.x, point.y - origin.y) < (tool == .finger ? 10 : 4) else {
                if scrollSwipes, time.isFinite, time >= began, time - began < Self.dragDelay {
                    return [.scrollBegin(origin, time: began), .scroll(point, time: time), .scrollEnd(time: time)]
                }
                return []
            }
            // Minor touch-up jitter remains a click at touch-down.
            let duration = time - began
            return [.click(origin, count: tool == .pencil && duration >= Self.pencilDoubleDelay ? 2 : 1,
                           secondary: tool == .finger && duration >= Self.contextDelay)]
        case .dragging: return [.move(point), .up(point)]
        case .scrolling: return [.scroll(point, time: time), .scrollEnd(time: time)]
        default: return []
        }
    }
    mutating func reset() { phase = .idle }
}
