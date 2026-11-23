import Foundation
@main struct DeviceIntegrationTests {
    static func main() {
        let suite = "henge.device-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID(), second = UUID()
        assert(DeviceIntegrationSettings.load(first, defaults: defaults) == DeviceIntegrationSettings())
        var value = DeviceIntegrationSettings(shareStatus: false, allowControls: true, gain: 0.4)
        value.save(first, defaults: defaults)
        assert(DeviceIntegrationSettings.load(first, defaults: defaults) == value)
        assert(DeviceIntegrationSettings.load(second, defaults: defaults) == DeviceIntegrationSettings())
        for (input, expected) in [(Double.nan, 1.0), (.infinity, 1.0), (-0.1, 0.0), (1.1, 1.0)] {
            value.gain = input; value.save(first, defaults: defaults)
            assert(DeviceIntegrationSettings.load(first, defaults: defaults).gain == expected)
        }
        defaults.set(Data("broken".utf8), forKey: "henge.device-integration.\(first.uuidString)")
        assert(DeviceIntegrationSettings.load(first, defaults: defaults) == DeviceIntegrationSettings())
        assert(HostDeviceValues.batteryPercent(0) == 0 && HostDeviceValues.batteryPercent(1) == 100)
        assert(HostDeviceValues.batteryPercent(0.574) == 57)
        for unknown in [-1.0, 1.01, .nan, .infinity] {
            assert(HostDeviceValues.batteryPercent(unknown) == -1 && HostDeviceValues.level(unknown) == -1)
        }
        assert(HostDeviceValues.level(0) == 0 && HostDeviceValues.level(1) == 1)
        print("PASS: per-VM settings, corrupt data, bounded levels and unknown battery state")
    }
}
