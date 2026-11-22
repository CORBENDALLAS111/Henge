import SwiftUI

struct TouchControlOptions: View {
    @Binding var mode: String
    @AppStorage(DirectContactGesture.scrollKey) private var oneFingerScrolling = DirectContactGesture.defaultOneFingerScrolling
    @AppStorage(DirectContactGesture.pencilTabletKey) private var pencilTablet = true
    @AppStorage(DirectMultiTouchGate.contextTapKey) private var twoFingerContextTap = false
    var body: some View {
        Picker("Control method", selection: $mode) {
            Text("Trackpad").tag("trackpad")
            Text("Direct Touch").tag("direct")
        }
        .pickerStyle(.segmented)
        Text(mode == "direct" ? "Touch the Mac's screen where you want to click. Hold still for a context menu."
             : "Swipe to move the pointer. Tap to click, or hold then move to drag.")
            .font(.footnote).foregroundStyle(.secondary)
        if mode == "direct" {
            Toggle("Two-finger tap for context menu", isOn: $twoFingerContextTap)
            Text("Optional: a quick stationary two-finger tap right-clicks between your fingers. Scrolling, pinch and long press keep their existing behavior.")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("One-finger scrolling", isOn: $oneFingerScrolling)
            Text(oneFingerScrolling
                 ? "Swipe to scroll. To drag immediately, tap, then touch the same object again and move without lifting. Or pause briefly before moving. Keep holding still for a context menu. Scrolling follows the Mac's natural direction and inertia settings. Apple Pencil still drags directly."
                 : "Move one finger to drag. Use two fingers to scroll, or enable one-finger scrolling above.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Toggle("Pencil as graphics tablet", isOn: $pencilTablet)
        Text(pencilTablet
             ? "The tip starts a stroke immediately. Pressure, tilt, orientation and supported Pencil Pro barrel roll go to the Mac's pen device. Double-tap and squeeze follow your Pencil settings."
             : "Pencil taps click; hold still then lift to double-click. Move to drag. Enable graphics tablet mode for drawing and pressure from the start of a stroke.")
            .font(.footnote).foregroundStyle(.secondary)
        NavigationLink("Gestures & Apple Pencil") { TouchGestureGuide() }
    }
}
