import SwiftUI

struct KeyboardOptions: View {
    @AppStorage(SessionKeyboard.modeKey) private var mode = "manual"
    @AppStorage(SessionKeyboard.keepSizeKey) private var keepSize = true
    var body: some View {
        Picker("Open keyboard", selection: $mode) {
            Text("Manually").tag("manual")
            Text("On direct taps").tag("tap")
            Text("On text fields").tag("text")
        }
        Toggle("Keep Mac screen size", isOn: $keepSize)
        Text("Direct taps opens the keyboard after a click, never after a swipe or drag. Text fields requires the current guest helper and Accessibility permission inside macOS. Smart touch also recognizes buttons, sliders and read-only controls so they do not trigger the text-field keyboard. Set up or update the helper in Details, Sharing. Field text is not read.")
            .font(.footnote).foregroundStyle(.secondary)
        Text("The Mac image moves up instead of shrinking. Drag Move Mac view above the keyboard to move the image vertically while the keyboard stays open. The keyboard button always works manually.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}
