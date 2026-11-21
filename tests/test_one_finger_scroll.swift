import Foundation
import CoreGraphics

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
        precondition(restarted.map { $0.1 } == [2,2,0,0], "restart releases previous contacts first")
        let cancel = touches(s.end(time: .nan))
        precondition(cancel.count == 2 && cancel.allSatisfy { $0.1 == 2 && $0.4 == 21000 })
        precondition(s.begin(p, size: .zero, time: 30).isEmpty)
        precondition(s.begin(p, size: CGSize(width: CGFloat.infinity, height: 100), time: 30).isEmpty)
        precondition(s.begin(p, size: size, time: .infinity).isEmpty)
        _ = s.begin(p, size: size, time: 31)
        precondition(touches(s.begin(p, size: .zero, time: 32)).allSatisfy { $0.1 == 2 } && !s.active)
        _ = s.begin(.zero, size: size, time: 40)
        let bounded = touches(s.move(CGPoint(x: -100000, y: 100000), time: 40.1))
        precondition(bounded.allSatisfy { (0...8134).contains($0.2) && (0...5206).contains($0.3) })
        _ = s.end(time: 40.2)
        print("PASS: one-finger native scroll contact ordering, source timestamps, axis lock, bounds, restart/cancel and invalid samples")
    }
}
