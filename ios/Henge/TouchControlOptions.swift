import SwiftUI

struct TouchControlOptions: View {
    @Binding var mode: String
    var body: some View {
        Picker("Control method", selection: $mode) {
            Text("Trackpad").tag("trackpad")
            Text("Direct Touch").tag("direct")
        }
        .pickerStyle(.segmented)
        Text(mode == "direct" ? "Touch the Mac's screen where you want to click. Hold still for a context menu."
             : "Swipe to move the pointer. Tap to click, or hold then move to drag.")
            .font(.footnote).foregroundStyle(.secondary)
        NavigationLink("Gestures & Apple Pencil") { TouchGestureGuide() }
    }
}
