import Foundation

struct DeviceIntegrationSettings: Codable, Equatable {
    var shareStatus = true
    var allowControls = false
    var gain = 1.0

    func normalized() -> Self {
        var value = self
        value.gain = gain.isFinite ? min(max(gain, 0), 1) : 1
        return value
    }
    private static func key(_ id: UUID) -> String { "henge.device-integration.\(id.uuidString)" }
    static func load(_ id: UUID, defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key(id)), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value.normalized()
    }
    func save(_ id: UUID, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(normalized()) else { return }
        defaults.set(data, forKey: Self.key(id))
    }
}

enum HostDeviceValues {
    static func batteryPercent(_ level: Double) -> Int32 {
        guard level.isFinite, level >= 0, level <= 1 else { return -1 }
        return Int32((level * 100).rounded())
    }
    static func level(_ value: Double) -> Double {
        value.isFinite && value >= 0 && value <= 1 ? value : -1
    }
}
