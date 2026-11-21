import Foundation

@main struct GuestResolutionTests {
    static func main() throws {
        precondition(GuestResolution(width: " 2560 ", height: "1440") == .qhd)
        for bad in ["", "2K", "0", "639", "7681", "99999999999999999999999"] {
            precondition(GuestResolution(width: bad, height: "1440") == nil)
        }
        precondition(GuestResolution(width: 3840, height: 2160) != nil)
        precondition(GuestResolution(width: 7680, height: 4320) == nil)
        precondition(GuestResolution(width: Int.max, height: Int.max) == nil)
        precondition(GuestResolution(width: 2560, height: 479) == nil)
        func selected(_ w: Int?, _ h: Int?, custom: Bool? = nil, retina: Bool? = nil) -> GuestResolution {
            GuestResolution.selected(width: w, height: h, custom: custom, retina: retina,
                isPad: true, nativeWidth: 2732, nativeHeight: 2048)
        }
        precondition(selected(nil, nil) == .fullHD, "old machines retain the default")
        precondition(selected(2560, 1440) == .qhd, "selected preset is passed through")
        precondition(selected(2560, 1440, custom: true, retina: true) == .qhd, "explicit custom pixels override a stale Retina flag")
        precondition(!GuestResolution.usesRetina(custom: true, retina: true, isPad: true))
        precondition(selected(2560, 1440, retina: true) == GuestResolution(width: 2732, height: 2048))
        precondition(selected(-1, 0) == .fullHD, "malformed saved modes never reach the GPU")
        let data = try JSONEncoder().encode(GuestResolution.qhd)
        let restored = try JSONDecoder().decode(GuestResolution.self, from: data)
        precondition(restored == .qhd)
        do {
            _ = try JSONDecoder().decode(GuestResolution.self, from: Data("{\"width\":0,\"height\":0}".utf8))
            preconditionFailure("invalid persisted dimensions must be rejected")
        } catch is DecodingError {}
        print("PASS: QHD preset, custom parsing/bounds, old defaults, explicit-pixel precedence over Retina, persistence")
    }
}
