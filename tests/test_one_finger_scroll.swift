import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@main struct OneFingerScrollTests {
    static func main() {
        var s = OneFingerScroll()
        let p = CGPoint(x: 200, y: 300), size = CGSize(width: 800, height: 600)
        func touches(_ events: [OneFingerScroll.Event]) -> [(Int32, Int32, Int32, Int32, UInt32)] {
            events.compactMap {
                if case let .touch(id, phase: phase, x: x, y: y, time: time) = $0 { return (id, phase, x, y, time) }
                return nil
            }
        }
        let down = touches(s.begin(p, size: size, time: 10))
        precondition(down.count == 2 && s.active)
        precondition(down[0].0 == 8 && down[1].0 == 9 && down.allSatisfy { $0.1 == 0 && $0.4 == 10000 })
        precondition(down[1].2 - down[0].2 == 200 && down[1].3 == down[0].3)
        let move = s.move(CGPoint(x: 202, y: 270), time: 10.02), mt = touches(move)
        precondition(mt.count == 2 && mt.allSatisfy { $0.1 == 1 && $0.4 == 10020 })
        precondition(mt[0].2 == down[0].2 && mt[0].3 < down[0].3, "dominant vertical movement locks horizontal drift")
        precondition(mt[1].3 == mt[0].3 && mt[1].2 - mt[0].2 == 200)
        precondition(move.last == .frame(10020), "one frame commits both virtual fingers together")
        precondition(s.move(CGPoint(x: 100, y: 100), time: 10.01).isEmpty, "out-of-order sample cannot create a speed spike")
        precondition(s.move(CGPoint(x: CGFloat.nan, y: 0), time: 10.03).isEmpty)
        precondition(s.move(CGPoint(x: 202, y: 270), time: 10.04).isEmpty, "no duplicate stationary frame on lift")
        let up = touches(s.end(time: 10.05))
        precondition(up.count == 2 && up.allSatisfy { $0.1 == 2 && $0.4 == 10050 })
        precondition(up[0].2 == mt[0].2 && up[0].3 == mt[0].3 && !s.active)
        precondition(s.end(time: 11).isEmpty && s.move(p, time: 11).isEmpty)

        _ = s.begin(p, size: size, time: 20)
        let horizontal = touches(s.move(CGPoint(x: 250, y: 302), time: 20.05))
        precondition(horizontal[0].2 > down[0].2 && horizontal[0].3 == down[0].3)
        let restarted = touches(s.begin(p, size: size, time: 21))
        precondition(restarted.suffix(4).map { $0.1 } == [2,2,0,0], "restart releases previous contacts first")
        let cancel = touches(s.end(time: .nan))
        precondition(cancel.count == 2 && cancel.allSatisfy { $0.1 == 2 && $0.4 == 21000 })
        precondition(s.begin(p, size: .zero, time: 30).isEmpty)
        precondition(s.begin(p, size: CGSize(width: CGFloat.infinity, height: 100), time: 30).isEmpty)
        precondition(s.begin(p, size: size, time: .infinity).isEmpty)
        _ = s.begin(p, size: size, time: 31)
        precondition(touches(s.begin(p, size: .zero, time: 32)).suffix(2).allSatisfy { $0.1 == 2 } && !s.active)
        _ = s.begin(.zero, size: size, time: 40)
        let bounded = touches(s.move(CGPoint(x: -100000, y: 100000), time: 40.1))
        precondition(bounded.allSatisfy { (0...8134).contains($0.2) && (0...5206).contains($0.3) })
        _ = s.end(time: 40.2)

        // Diagonal content (maps, wide documents) must keep both directions.
        let diagonalDown = touches(s.begin(p, size: size, time: 50))
        let diagonal = touches(s.move(CGPoint(x: 220, y: 320), time: 50.02))
        precondition(diagonal[0].2 > diagonalDown[0].2 && diagonal[0].3 > diagonalDown[0].3)
        _ = s.end(time: 50.03)

        // UIKit keeps reporting a captured finger beyond the view's edge.
        // Reversal must move immediately, without paying back that overshoot.
        _ = s.begin(p, size: size, time: 60)
        let edge = touches(s.move(CGPoint(x: 200, y: -1000), time: 60.02))
        precondition(edge[0].3 == 0)
        let reversal = touches(s.move(CGPoint(x: 200, y: -990), time: 60.04))
        precondition(reversal[0].3 > 0 && reversal[0].3 < 100)
        _ = s.end(time: 60.05)

        // A continuing flick goes straight to release, leaving inertia to macOS.
        _ = s.begin(p, size: size, time: 70)
        _ = s.move(CGPoint(x: 200, y: 280), time: 70.02)
        precondition(touches(s.end(time: 70.03)).map { $0.1 } == [2, 2])
        // A deliberate pause emits one stationary pair before release so the
        // driver does not reuse the old swipe velocity and launch another fling.
        _ = s.begin(p, size: size, time: 80)
        let moving = touches(s.move(CGPoint(x: 200, y: 280), time: 80.02))
        let paused = s.end(time: 80.2), pausedTouches = touches(paused)
        precondition(pausedTouches.map { $0.1 } == [1, 1, 2, 2])
        precondition(pausedTouches.allSatisfy { $0.4 == 80200 })
        precondition(pausedTouches[0].2 == moving[0].2 && pausedTouches[0].3 == moving[0].3)
        precondition(paused[2] == .frame(80200), "settled contacts are committed before lift")

        _ = s.begin(p, size: size, time: 90)
        _ = s.move(CGPoint(x: 200, y: 280), time: 90.02)
        precondition(touches(s.move(CGPoint(x: 200, y: 280), time: 90.2)).count == 2)
        precondition(s.move(CGPoint(x: 200, y: 280), time: 90.3).isEmpty, "settle only once until motion resumes")
        precondition(touches(s.end(time: 90.4)).map { $0.1 } == [2, 2])
        print("PASS: native scroll ordering/timing, axis lock and diagonal pans, edge reversal, pause/flick release, bounds and cancellation")
    }
}
