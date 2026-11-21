import Foundation

/// Guest pixels, separate from iPad points and macOS's Retina "Looks like" size.
struct GuestResolution: Codable, Hashable {
    let width: Int
    let height: Int
    static let fullHD = GuestResolution(width: 1920, height: 1080)!
    static let qhd = GuestResolution(width: 2560, height: 1440)!

    init?(width: Int, height: Int) {
        guard (640...7680).contains(width), (480...4320).contains(height),
              width * height <= 8_294_400 else { return nil }
        self.width = width; self.height = height
    }
    init?(width: String, height: String) {
        guard let w = Int(width.trimmingCharacters(in: .whitespacesAndNewlines)),
              let h = Int(height.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.init(width: w, height: h)
    }
    private enum CodingKeys: String, CodingKey { case width, height }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let w = try c.decode(Int.self, forKey: .width), h = try c.decode(Int.self, forKey: .height)
        guard let size = Self(width: w, height: h) else {
            throw DecodingError.dataCorruptedError(forKey: .width, in: c, debugDescription: "Unsupported guest pixel dimensions")
        }
        self = size
    }
    static func usesRetina(custom: Bool?, retina: Bool?, isPad: Bool) -> Bool {
        isPad && retina == true && custom != true
    }
    static func selected(width: Int?, height: Int?, custom: Bool?, retina: Bool?,
                         isPad: Bool, nativeWidth: Int, nativeHeight: Int) -> Self {
        if usesRetina(custom: custom, retina: retina, isPad: isPad) {
            return Self(width: nativeWidth, height: nativeHeight) ?? .fullHD
        }
        return Self(width: width ?? 1920, height: height ?? 1080) ?? .fullHD
    }
}
