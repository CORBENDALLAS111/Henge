import SwiftUI

struct TouchGestureGuide: View {
    @AppStorage(DirectContactGesture.scrollKey) private var oneFingerScrolling = DirectContactGesture.defaultOneFingerScrolling
    var body: some View {
        Form {
            Section("Direct Touch") {
                LabeledContent("Click", value: "Tap once")
                LabeledContent("Double-click", value: "Tap twice")
                LabeledContent("Drag or select", value: oneFingerScrolling ? "Pause briefly, then move" : "Touch and move")
                LabeledContent("Context menu", value: "Hold still")
                LabeledContent("Scroll", value: oneFingerScrolling ? "Swipe with one finger" : "Move two fingers")
                Text("Change one-finger scrolling in Touch Controls. When enabled, swipe to scroll, or pause for about a quarter second before moving to drag. Keep holding still for the context menu. Two-finger scrolling is also available. macOS supplies the scrolling direction and inertia; Pencil dragging is unchanged.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Tapping with two fingers does not click in Direct Touch. Use a one-finger hold for the context menu. Tap the hand/trackpad icon in the session bar to switch control methods.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Small movements during a tap are ignored. A contact circle follows your finger and disappears when you lift. The mouse arrow appears again for Pencil hover or a connected mouse.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Apple Pencil") {
                LabeledContent("Hover", value: "Move the tip above the screen")
                LabeledContent("Click", value: "Touch and lift")
                LabeledContent("Double-click", value: "Hold still briefly, then lift")
                LabeledContent("Drag or select", value: "Touch and move")
                Text("Hold the tip still for about half a second, then lift to double-click. Moving before lifting starts a drag instead. Pressure and tilt are sent while dragging; supported Pencil Pro hardware also sends barrel roll.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Barrel double-tap and Pencil Pro squeeze follow your Pencil preferences in the device's Settings. Eraser actions switch tools; palette actions open a context menu at the hovered point. Hover needs a compatible iPad and Pencil.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Trackpad") {
                Text("Swipe to move, tap to click, tap twice to double-click. Hold still then move to drag. Two fingers scroll or tap for a context menu. Pencil continues to point directly on the Mac image.")
            }
            Section("Connected displays and devices") {
                Text("When the Mac is on an external display, this screen remains a trackpad. Touch and Pencil pause while a physical mouse is connected. Tap with four fingers to reveal hidden session controls.")
                Text("After updating the input device, shut down the Mac and start it again so macOS loads the current device configuration.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Desk.page)
        .navigationTitle("Gestures & Apple Pencil")
        .navigationBarTitleDisplayMode(.inline)
    }
}
