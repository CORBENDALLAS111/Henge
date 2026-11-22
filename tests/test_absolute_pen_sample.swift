import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@main struct AbsolutePenSampleTests {
    static func main() {
        let size = CGSize(width: 800, height: 600)
        let middle = AbsolutePenSample(point: CGPoint(x: 400, y: 300), size: size, pressure: 0.5, flags: 5)
        precondition(middle.x == 16384 && middle.y == 16384 && middle.pressure == 2048)
        let boxed = AbsolutePenSample(point: CGPoint(x: 500, y: 400), imageFrame: CGRect(x: 100, y: 100, width: 800, height: 600), pressure: 0.5, flags: 5)
        precondition(boxed.x == middle.x && boxed.y == middle.y && boxed.pressure == middle.pressure)
        let zoomed = AbsolutePenSample(point: CGPoint(x: 400, y: 300), imageFrame: CGRect(x: -400, y: -300, width: 1600, height: 1200), pressure: 0, flags: 4)
        precondition(zoomed.x == middle.x && zoomed.y == middle.y && zoomed.pressure == 0)
        let edge = AbsolutePenSample(point: CGPoint(x: 900, y: -3), size: size, pressure: 2, altitude: .pi / 4, azimuth: 0, roll: -.pi / 2, flags: 5)
        precondition(edge.x == 32767 && edge.y == 0 && edge.pressure == 4095)
        precondition(abs(edge.tiltX - 4500) <= 1 && abs(edge.tiltY) <= 1 && edge.twist == 27000)
        let up = AbsolutePenSample(point: .zero, size: size, pressure: 1, flags: 4)
        precondition(up.pressure == 0 && up.tiltX == 0 && up.tiltY == 0)
        let invalid = AbsolutePenSample(point: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), size: .zero, pressure: .nan, altitude: .nan, azimuth: .nan, roll: .nan, flags: 5)
        precondition(invalid.x == 0 && invalid.y == 0 && invalid.pressure == 1 && invalid.twist == 0)
        print("PASS: absolute coordinate mapping, bounds, pressure, tilt, barrel roll and nonfinite input")
    }
}
