import Foundation

@main struct GamepadSampleTests {
    static func main() {
        let directions: [(Float, Float)] = [(0,1),(1,1),(1,0),(1,-1),(0,-1),(-1,-1),(-1,0),(-1,1),(0,0)]
        for (hat, direction) in directions.enumerated() {
            precondition(GamepadSample(buttons: 0, dpadX: direction.0, dpadY: direction.1).hat == Int32(hat))
        }
        let full = GamepadSample(buttons: 0xffff, dpadX: 0, dpadY: 0, leftX: 1, leftY: 1,
                                 rightX: -1, rightY: -1, leftTrigger: 1, rightTrigger: 3)
        precondition(full.buttons == 0xffff && full.axes == [32767, -32767, -32767, 32767, 32767, 32767])
        let bad = GamepadSample(buttons: 0, dpadX: .nan, dpadY: .infinity, leftX: .infinity, leftY: -.infinity,
                                rightX: .nan, rightY: 0.05, leftTrigger: -1, rightTrigger: .nan)
        precondition(bad.hat == 8 && bad.axes == [0, 0, 0, 0, 0, 0])
        let half = GamepadSample(buttons: 1, dpadX: 0, dpadY: 0, leftX: 0.53, leftTrigger: 0.5)
        precondition(abs(half.axes[0] - 16384) <= 1 && half.axes[4] == 16384)
        print("PASS: gamepad hat directions, axes/triggers, dead zone, buttons and nonfinite input")
    }
}
