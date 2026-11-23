import SwiftUI
import UIKit
import AVFAudio
import GameController
import MediaPlayer

@MainActor final class HostDeviceBridge: ObservableObject {
    private let macID: UUID
    private var activeSession: UInt64 = 0
    private var previouslyMonitoring = false
    @Published var settings: DeviceIntegrationSettings {
        didSet {
            settings.save(macID)
            _ = henge_vm_audio_gain(settings.normalized().gain)
        }
    }
    @Published private(set) var battery: Int32 = -1
    @Published private(set) var brightness = Double(UIScreen.main.brightness)

    init(macID: UUID) {
        self.macID = macID
        settings = DeviceIntegrationSettings.load(macID)
        _ = henge_vm_audio_gain(settings.gain)
    }

    func refreshBrightness() { brightness = Double(UIScreen.main.brightness) }
    func setBrightness(_ value: Double) {
        guard value.isFinite, (0...1).contains(value) else { return }
        UIScreen.main.brightness = CGFloat(value)
        refreshBrightness()
    }

    /// A cancelled old task can never stop a newer foreground/permission lease.
    func follow(active: Bool, external: @escaping @MainActor () -> Bool) async {
        guard active else { return }
        if activeSession == 0 { previouslyMonitoring = UIDevice.current.isBatteryMonitoringEnabled }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let session = henge_share_device_begin(settings.allowControls ? 1 : 0)
        activeSession = session
        defer {
            henge_share_device_stop(session)
            if activeSession == session {
                activeSession = 0
                UIDevice.current.isBatteryMonitoringEnabled = previouslyMonitoring
            }
        }
        var ticks = 0, status = collect(external: external())
        while !Task.isCancelled && activeSession == session {
            if ticks % 10 == 0 { status = collect(external: external()) }
            // Observe local edits before consuming queued guest changes.
            status.brightness = HostDeviceValues.level(Double(UIScreen.main.brightness))
            status.vm_gain = henge_vm_audio_current_gain()
            _ = henge_share_device_publish(session, &status)
            for _ in 0..<4 {
                var field: Int32 = 0, revision: UInt64 = 0, value = 0.0
                guard henge_share_device_take(session, &field, &revision, &value) != 0 else { break }
                if field == 0 { settings.gain = value }
                else if field == 1 { UIScreen.main.brightness = CGFloat(value) }
                let actual = field == 0 ? henge_vm_audio_current_gain() : Double(UIScreen.main.brightness)
                _ = henge_share_device_ack(session, field, revision, actual)
                status.vm_gain = henge_vm_audio_current_gain()
                status.brightness = HostDeviceValues.level(Double(UIScreen.main.brightness))
                _ = henge_share_device_publish(session, &status)
            }
            brightness = status.brightness
            ticks += 1
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { break }
        }
    }

    private func collect(external: Bool) -> HvHostDeviceStatus {
        var status = HvHostDeviceStatus()
        status.battery = HostDeviceValues.batteryPercent(Double(UIDevice.current.batteryLevel))
        battery = status.battery
        status.power = Int32(UIDevice.current.batteryState.rawValue)
        status.low_power = ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 : 0
        status.thermal = Int32(ProcessInfo.processInfo.thermalState.rawValue)
        status.external_display = external ? 1 : 0
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: status.host_kind = 0
        case .pad: status.host_kind = 1
        default: status.host_kind = 2
        }
        status.system_volume = HostDeviceValues.level(Double(AVAudioSession.sharedInstance().outputVolume))
        status.brightness = HostDeviceValues.level(Double(UIScreen.main.brightness))
        status.vm_gain = henge_vm_audio_current_gain()
        var route: UInt32 = 0
        for output in AVAudioSession.sharedInstance().currentRoute.outputs {
            switch output.portType {
            case .builtInSpeaker: route |= 1
            case .builtInReceiver: route |= 2
            case .headphones, .lineOut: route |= 4
            case .usbAudio: route |= 8
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: route |= 16
            case .airPlay: route |= 32
            case .HDMI, .displayPort: route |= 64
            default: route |= 128
            }
        }
        status.audio_route = route
        status.peripherals = (GCKeyboard.coalesced != nil ? 1 : 0) |
            (HardwareMouse.shared.hasMouse ? 2 : 0) | (!GCController.controllers().isEmpty ? 4 : 0)
        return status
    }
}

struct DeviceBridgeActivity: Equatable { let active: Bool; let controls: Bool }

/// A visible public system volume control. Guest commands never manipulate its
/// internal subviews or claim to set AVAudioSession's readonly system volume.
struct SystemVolumeControl: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.showsRouteButton = false
        view.accessibilityLabel = "Device system volume"
        return view
    }
    func updateUIView(_ view: MPVolumeView, context: Context) { }
}

struct DeviceIntegrationOptions: View {
    @ObservedObject var bridge: HostDeviceBridge
    var body: some View {
        Toggle("Share device status with macOS", isOn: $bridge.settings.shareStatus)
        if bridge.settings.shareStatus {
            Toggle("Allow guest brightness and Mac audio controls", isOn: $bridge.settings.allowControls)
            Text("The updated guest helper shows charge, power, thermal state, peripherals and active audio/video outputs in its Henge menu. Guest controls apply only while Henge is active. They change the device screen brightness and this VM's audio level.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        LabeledContent("Mac audio level", value: "\(Int(bridge.settings.gain * 100))%")
        Slider(value: $bridge.settings.gain, in: 0...1).accessibilityLabel("Mac audio level")
        LabeledContent("Device brightness", value: bridge.brightness >= 0 ? "\(Int(bridge.brightness * 100))%" : "Unknown")
        Slider(value: Binding(get: { bridge.brightness }, set: { bridge.setBrightness($0) }), in: 0...1)
            .accessibilityLabel("Device screen brightness")
            .onAppear { bridge.refreshBrightness() }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in bridge.refreshBrightness() }
        Text("Device system volume")
        SystemVolumeControl().frame(height: 32)
        Text("The system slider changes iPad/iPhone volume. The Mac audio level affects only this VM. Audio routes remain managed by iPadOS. Device brightness is separate from the Mac image's Brightness setting above.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}
