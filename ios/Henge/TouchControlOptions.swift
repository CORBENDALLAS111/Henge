import SwiftUI

struct TouchControlOptions: View {
    @Binding var mode: String
    @AppStorage(DirectContactGesture.scrollKey) private var oneFingerScrolling = false
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
            Toggle("One-finger scrolling", isOn: $oneFingerScrolling)
            Text(oneFingerScrolling
                 ? "Swipe to scroll. To drag, pause briefly before moving; keep holding still for a context menu. Scrolling follows the Mac's natural direction and inertia settings. Apple Pencil still drags directly."
                 : "Move one finger to drag. Use two fingers to scroll, or enable one-finger scrolling above.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        NavigationLink("Gestures & Apple Pencil") { TouchGestureGuide() }
    }
}
