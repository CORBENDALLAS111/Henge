import Foundation

@main struct GuestTouchObjectTests {
    static func main() {
        let rect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        func object(_ kind: Int32, _ caps: UInt32, _ bounds: CGRect? = nil) -> GuestTouchObject? {
            GuestTouchObject(kind: kind, capabilities: caps, bounds: bounds ?? rect)
        }
        precondition(object(7, 260)?.keyboardEditable == true)
        precondition(object(7, 256)?.keyboardEditable == false)
        precondition(object(7, 0)?.keyboardEditable == nil, "failed editability query is not readonly")
        precondition(object(7, 32)?.keyboardEditable == false)
        precondition(object(9, 16)?.keyboardEditable == false)
        precondition(object(0, 0)?.keyboardEditable == nil, "legacy hints keep focus-based keyboard behavior")
        precondition(object(4, 65)?.preciseDrag == true)
        precondition(object(9, 16)?.isolatedPress == true)
        precondition(object(9, 18)?.isolatedPress == false, "button in scroll container must permit scrolling")
        precondition(object(9, 260) == nil && object(7, 4) == nil)
        precondition(object(4, 193) == nil && object(1, 64) == nil)
        precondition(object(4, 33) == nil && object(14, 0) == nil && object(0, 512) == nil)
        precondition(object(4, 1, CGRect(x: 0.9, y: 0, width: 0.2, height: 1)) == nil)
        precondition(object(4, 1, CGRect(x: 0, y: 0, width: -1, height: 1)) == nil)
        precondition(object(4, 1, CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1)) == nil)
        let mapped = object(9, 16)!.frame(in: CGRect(x: -100, y: 50, width: 800, height: 600))
        precondition(abs(mapped.minX + 20) < 0.001 && abs(mapped.minY - 170) < 0.001)
        precondition(abs(mapped.width - 240) < 0.001 && abs(mapped.height - 240) < 0.001)
        print("PASS: semantic object validation, readonly/unknown fields, controls, capability safety and scaled/panned geometry")
    }
}
