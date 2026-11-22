import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Desktop gesture classification in view points, before any guest button-down.
/// A held Pencil produces a double-click only on lift, so it can still become a drag.
struct DirectContactGesture {
    enum Tool { case finger, pencil }
    enum TargetHint: Int32 { case automatic = 0, drag = 1, scroll = 2 }
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
    private var previousTap: (point: CGPoint, time: TimeInterval)?
    private var tapDrag = false
    private var targetHint = TargetHint.automatic
    private var targetPending = false
    var awaitingTarget: Bool { phase == .pending && targetPending }
    static let scrollKey = "henge.touch.oneFingerScrolling"
    static let defaultOneFingerScrolling = true
    static let pencilTabletKey = "henge.pencil.graphicsTablet"
    static let dragDelay: TimeInterval = 0.22
    static let contextDelay: TimeInterval = 0.55
    static let pencilDoubleDelay: TimeInterval = 0.45
    static let tapDragInterval: TimeInterval = 0.35
    static let tapDragDistance: CGFloat = 24
    static let smartTargetsKey = "henge.touch.smartTargets"
    static let targetWait: TimeInterval = 0.120 // host/touch_target.h protocol lifetime

    /// A reply belongs only to this still-undecided contact. Never change a
    /// button/gesture already delivered to macOS, or apply a late app response.
    @discardableResult mutating func resolveTarget(_ hint: TargetHint, time: TimeInterval) -> Bool {
        guard awaitingTarget, time.isFinite, time >= began, time - began <= Self.targetWait else { return false }
        targetPending = false; targetHint = hint
        return true
    }
    mutating func expireTarget() { targetPending = false }

    /// Joining a second finger must not turn an existing drag/scroll/context
    /// action into a new click, even if the first finger returns to its origin.
    func canJoinContextTap(at point: CGPoint) -> Bool {
        phase == .pending && tool == .finger && hypot(point.x - origin.x, point.y - origin.y) < 8
    }

    @discardableResult
    mutating func begin(_ point: CGPoint, tool: Tool, time: TimeInterval, scrollFingerSwipes: Bool = false,
                        pencilTablet: Bool = false, awaitTarget: Bool = false) -> [Action] {
        self.tool = tool; origin = point; began = time; phase = .pending
        scrollSwipes = scrollFingerSwipes && tool == .finger
        targetHint = .automatic
        targetPending = scrollSwipes && awaitTarget
        tapDrag = false
        if scrollSwipes, let tap = previousTap, time.isFinite, time >= tap.time,
           time - tap.time <= Self.tapDragInterval,
           hypot(point.x - tap.point.x, point.y - tap.point.y) <= Self.tapDragDistance {
            tapDrag = true
        }
        previousTap = nil
        if tapDrag { targetPending = false } // explicit user intent always wins
        if pencilTablet && tool == .pencil {
            phase = .dragging
            return [.down(point)]
        }
        return []
    }
    mutating func move(_ point: CGPoint, time: TimeInterval? = nil) -> [Action] {
        guard point.x.isFinite, point.y.isFinite else { return [] }
        if let time, !time.isFinite || time < began { return [] }
        switch phase {
        case .pending:
            let distance = hypot(point.x - origin.x, point.y - origin.y)
            guard distance >= (tool == .finger ? 10 : 4) else { return [] }
            if targetPending {
                if let time, time - began < Self.targetWait { return [] }
                targetPending = false
            }
            if scrollSwipes, !tapDrag, targetHint != .drag, let time, time.isFinite, time >= began,
               targetHint == .scroll || time - began < Self.dragDelay {
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
        guard phase == .pending, tool == .finger, time.isFinite, time - began >= Self.contextDelay else { return [] }
        phase = .consumed
        return [.click(origin, count: 1, secondary: true)]
    }
    mutating func end(_ point: CGPoint, time: TimeInterval) -> [Action] {
        defer { phase = .idle; tapDrag = false; targetPending = false }
        switch phase {
        case .pending:
            guard point.x.isFinite, point.y.isFinite, time.isFinite, time >= began else { return [] }
            // A flick can end before UIKit supplies a move sample. It is not a
            // stationary tap and must not click or auto-open the keyboard.
            guard hypot(point.x - origin.x, point.y - origin.y) < (tool == .finger ? 10 : 4) else {
                if tapDrag || targetHint == .drag { return [.down(origin), .move(point), .up(point)] }
                if scrollSwipes, targetHint == .scroll || time - began < Self.dragDelay {
                    return [.scrollBegin(origin, time: began), .scroll(point, time: time), .scrollEnd(time: time)]
                }
                return []
            }
            // Minor touch-up jitter remains a click at touch-down.
            let duration = time - began
            if scrollSwipes, duration < Self.contextDelay { previousTap = (origin, time) }
            return [.click(origin, count: tool == .pencil && duration >= Self.pencilDoubleDelay ? 2 : 1,
                           secondary: tool == .finger && duration >= Self.contextDelay)]
        case .dragging: return [.move(point), .up(point)]
        case .scrolling: return [.scroll(point, time: time), .scrollEnd(time: time)]
        default: return []
        }
    }
    mutating func reset() { phase = .idle; previousTap = nil; tapDrag = false; targetPending = false; targetHint = .automatic }
}
