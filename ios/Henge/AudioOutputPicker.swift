import SwiftUI
import AVKit
import AVFAudio

/// iPadOS owns Bluetooth audio pairing/routing; the guest keeps its existing
/// virtual sound card and Core Audio follows this output route.
struct AudioOutputPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.accessibilityLabel = "Audio output"
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) { }

    static var routeDescription: String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        if outputs.contains(where: { [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType) }) { return "Bluetooth audio" }
        if outputs.contains(where: { $0.portType == .airPlay }) { return "AirPlay" }
        if outputs.contains(where: { $0.portType == .headphones || $0.portType == .usbAudio }) { return "Wired or USB audio" }
        return "Device output"
    }
}
