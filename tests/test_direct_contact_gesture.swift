import Foundation
import CoreGraphics

@main struct DirectContactGestureTests {
    static func main() {
        var g = DirectContactGesture()
        let p = CGPoint(x: 100, y: 200), jitter = CGPoint(x: 103, y: 202), moved = CGPoint(x: 125, y: 200)
        for tool in [DirectContactGesture.Tool.finger, .pencil] {
            g.begin(p, tool: tool, time: 1)
            precondition(g.move(jitter).isEmpty, "jitter must never press the guest button")
            precondition(g.end(jitter, time: 1.2) == [.click(p, count: 1, secondary: false)])
            g.begin(p, tool: tool, time: 1.5)
            precondition(g.end(moved, time: 1.51).isEmpty, "a swipe without delivered move samples must not click")
            g.begin(p, tool: tool, time: 2)
            precondition(g.move(moved) == [.down(p), .move(moved)], "drag starts at the touched object")
            precondition(g.hold(time: 3).isEmpty, "a drag must not turn into right/double-click")
            precondition(g.end(moved, time: 3) == [.move(moved), .up(moved)])
            precondition(g.end(moved, time: 3).isEmpty, "no duplicate lift")
            g.begin(p, tool: tool, time: 4); g.reset()
            precondition(g.hold(time: 5).isEmpty && g.end(p, time: 5).isEmpty, "cancel/multitouch suppresses clicks")
        }
        g.begin(p, tool: .finger, time: 10)
        precondition(g.hold(time: 10.54).isEmpty)
        precondition(g.hold(time: 10.56) == [.click(p, count: 1, secondary: true)])
        precondition(g.move(moved).isEmpty && g.end(moved, time: 11).isEmpty, "context action consumes the gesture")
        g.begin(p, tool: .finger, time: 12)
        precondition(g.end(jitter, time: 13) == [.click(p, count: 1, secondary: true)], "late timer still gives right-click")
        g.begin(p, tool: .pencil, time: 14)
        precondition(g.hold(time: 15).isEmpty, "Pencil hold cannot click while still touching")
        precondition(g.end(jitter, time: 15) == [.click(p, count: 2, secondary: false)])
        g.begin(p, tool: .pencil, time: 16)
        precondition(g.hold(time: 17).isEmpty)
        precondition(g.move(moved) == [.down(p), .move(moved)], "held Pencil may still drag")
        precondition(g.end(moved, time: 18) == [.move(moved), .up(moved)])
        for t in [20.0, 20.15] {
            g.begin(p, tool: .finger, time: t)
            precondition(g.end(p, time: t + 0.05) == [.click(p, count: 1, secondary: false)])
        }
        var multi = DirectMultiTouchGate()
        multi.begin(count: 2, time: 30)
        precondition(!multi.move(distance: 0, count: 2) && !multi.forwarding)
        precondition(!multi.move(distance: 7, count: 2) && !multi.reveal(time: 30.1), "two-finger tap emits no native trackpad input")
        precondition(!multi.move(distance: 10, count: 1), "lifting one finger cannot become a one-finger pointer jump")
        precondition(multi.move(distance: 10, count: 2) && multi.forwarding, "movement activates native scrolling")
        precondition(!multi.move(distance: 20, count: 2), "start native gesture only once")
        precondition(!multi.reveal(time: 30.2))
        multi.reset(); multi.begin(count: 2, time: 40); multi.begin(count: 4, time: 40.05)
        precondition(multi.reveal(time: 40.2), "four-finger control reveal still works without forwarding a tap")
        precondition(!multi.reveal(time: 41))
        multi.reset(); multi.begin(count: 4, time: 50)
        precondition(multi.move(distance: 9, count: 4) && !multi.reveal(time: 50.2))
        multi.reset(); multi.begin(count: 1, time: 60)
        precondition(!multi.move(distance: .nan, count: 1) && multi.move(distance: 9, count: 1))
        print("PASS: finger/Pencil jitter, clicks, double-click, hold context menu, drag and cancellation")
    }
}
