import SwiftUI
import UIKit

/// Types into the Mac. Two invisible views take turns holding the keyboard: one that asks for the
/// on-screen keyboard, with a row of the Mac's own keys above it, and one that doesn't, so that a
/// hardware keyboard works whether or not that is open.
struct KeyboardCatcher: UIViewRepresentable {
    @Binding var active: Bool

    func makeUIView(context: Context) -> Holder { Holder() }

    func updateUIView(_ view: Holder, context: Context) {
        view.typer.onHide = { active = false }
        view.typing = active
        DispatchQueue.main.async { view.takeKeyboard() }
    }

    final class Holder: UIView {
        let listener = KeyListener()
        let typer = CatcherView()
        var typing = false
        private var hiding: NSObjectProtocol?

        override init(frame: CGRect) {
            super.init(frame: frame)
            addSubview(listener)
            addSubview(typer)
            hiding = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification,
                                                            object: nil, queue: .main) { [weak self] _ in
                self?.keyboardHid()
            }
        }

        required init?(coder: NSCoder) { fatalError("made in code") }

        deinit {
            if let hiding { NotificationCenter.default.removeObserver(hiding) }
        }

        /// iPadOS's own hide-keyboard key closes the keyboard without asking the app, which then went on
        /// keeping the Mac small, with room for a keyboard that was gone. Stop typing as the row's button does.
        /// A sheet taking the keyboard isn't that: it is handed back when the sheet closes.
        private func keyboardHid() {
            guard typing, let window, window.rootViewController?.presentedViewController == nil else { return }
            typer.onHide()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            takeKeyboard()
        }

        /// Called often, which also takes the keyboard back after a sheet has had it.
        func takeKeyboard() {
            guard let window, window.rootViewController?.presentedViewController == nil else { return }
            let holder: UIView = typing ? typer : listener
            if !holder.isFirstResponder { holder.becomeFirstResponder() }
        }
    }

    /// Whichever view holds the keyboard hears a hardware keyboard's keys here.
    class KeyListener: UIView {
        override var canBecomeFirstResponder: Bool { true }
        /// Fingers belong to the session (they drive the Mac's trackpad), not to iPadOS's undo/copy/paste bar.
        override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let rest = HardwareKeys.send(presses, down: true)
            if !rest.isEmpty { super.pressesBegan(rest, with: event) }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let rest = HardwareKeys.send(presses, down: false)
            if !rest.isEmpty { super.pressesEnded(rest, with: event) }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let rest = HardwareKeys.send(presses, down: false)
            if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
        }
    }

    final class CatcherView: KeyListener, UIKeyInput {
        var onHide: () -> Void = {}
        private lazy var row: UIHostingController<ModifierRow> = {
            let host = UIHostingController(rootView: ModifierRow(hide: { [weak self] in self?.onHide() }))
            host.sizingOptions = []
            host.view.backgroundColor = .clear
            host.view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 56)
            host.view.autoresizingMask = .flexibleWidth
            return host
        }()

        override var inputAccessoryView: UIView? { row.view }
        var hasText: Bool { true }
        var autocorrectionType: UITextAutocorrectionType = .no
        var autocapitalizationType: UITextAutocapitalizationType = .none
        var spellCheckingType: UITextSpellCheckingType = .no
        var smartQuotesType: UITextSmartQuotesType = .no
        var smartDashesType: UITextSmartDashesType = .no

        func insertText(_ text: String) {
            guard !HardwareKeys.keyJustPressed else { return }
            for c in text { Keys.type(c) }
            StickyKeys.shared.releaseOneShot()
        }

        func deleteBackward() {
            guard !HardwareKeys.keyJustPressed else { return }
            Keys.press(Keys.backspace)
            StickyKeys.shared.releaseOneShot()
        }
    }
}

/// Linux input key codes, which the Mac's keyboard device takes.
enum Keys {
    static let backspace: UInt16 = 14
    static let shift: UInt16 = 42
    static let escape: UInt16 = 1
    static let tab: UInt16 = 15
    static let control: UInt16 = 29
    static let option: UInt16 = 56
    static let command: UInt16 = 125
    static let up: UInt16 = 103
    static let left: UInt16 = 105
    static let right: UInt16 = 106
    static let down: UInt16 = 108
    private static let letters: [Character: UInt16] = [
        "q": 16, "w": 17, "e": 18, "r": 19, "t": 20, "y": 21, "u": 22, "i": 23, "o": 24, "p": 25,
        "a": 30, "s": 31, "d": 32, "f": 33, "g": 34, "h": 35, "j": 36, "k": 37, "l": 38,
        "z": 44, "x": 45, "c": 46, "v": 47, "b": 48, "n": 49, "m": 50,
    ]
    private static let plain: [Character: UInt16] = [
        "1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7, "7": 8, "8": 9, "9": 10, "0": 11,
        "-": 12, "=": 13, "\t": 15, "[": 26, "]": 27, "\n": 28, ";": 39, "'": 40, "`": 41, "\\": 43,
        ",": 51, ".": 52, "/": 53, " ": 57,
    ]
    private static let shifted: [Character: UInt16] = [
        "!": 2, "@": 3, "#": 4, "$": 5, "%": 6, "^": 7, "&": 8, "*": 9, "(": 10, ")": 11,
        "_": 12, "+": 13, "{": 26, "}": 27, ":": 39, "\"": 40, "~": 41, "|": 43,
        "<": 51, ">": 52, "?": 53,
    ]

    static func press(_ code: UInt16, shifted: Bool = false) {
        GuestModifiers.withHeld(shifted ? [shift] : []) {
            henge_vm_key(code, 1)
            henge_vm_key(code, 0)
        }
    }

    /// A letter (or space) with a modifier held.
    static func chord(_ modifier: UInt16, _ c: Character) {
        GuestModifiers.withHeld([modifier]) { type(c) }
    }

    /// One character at a time, for what the Mac has to keep up with.
    @MainActor static func typeSlowly(_ text: String) async {
        for c in text {
            type(c)
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    static func type(_ c: Character) {
        if let code = letters[c] { press(code) }
        else if let lower = c.lowercased().first, let code = letters[lower] { press(code, shifted: true) }
        else if let code = plain[c] { press(code) }
        else if let code = shifted[c] { press(code, shifted: true) }
    }
}

/// All modifier-producing host paths share one ownership table, on the UI
/// thread. Shortcut owners are unique so nested shifted typing is safe too.
enum GuestModifiers {
    private static var ownership = ModifierOwnership()
    static func set(_ code: UInt16, owner: ModifierOwnership.Owner, down: Bool) {
        if let event = ownership.set(code, owner: owner, down: down) { send(event) }
    }
    static func release(_ owner: ModifierOwnership.Owner) {
        for event in ownership.release(owner) { send(event) }
    }
    static func withHeld(_ codes: [UInt16], perform: () -> Void) {
        let owner = ModifierOwnership.Owner.shortcut(UUID())
        for code in codes { set(code, owner: owner, down: true) }
        defer { release(owner) }
        perform()
    }
    private static func send(_ event: ModifierOwnership.Transition) {
        henge_vm_key(event.code, event.down ? 1 : 0)
    }
}

/// Modifiers stay down until the next key/click, or until unlocked.
final class StickyKeys: ObservableObject {
    static let shared = StickyKeys()
    @Published private(set) var state = StickyModifierState()
    var down: Set<UInt16> { state.down }
    var locked: Set<UInt16> { state.locked }

    private var revision: UInt64 = 0

    func toggle(_ code: UInt16) {
        update { $0.toggle(code) }
    }
    func toggleLock(_ code: UInt16) { update { $0.toggleLock(code) } }

    private func update(_ change: (inout StickyModifierState) -> Void) {
        revision &+= 1
        let before = state.down
        var next = state
        change(&next)
        for code in before.subtracting(next.down).sorted() { GuestModifiers.set(code, owner: .sticky, down: false) }
        for code in next.down.subtracting(before).sorted() { GuestModifiers.set(code, owner: .sticky, down: true) }
        state = next
    }

    /// Pointer reports may still be queued when the finger lifts. Keep a
    /// sticky modifier until the click has actually reached the guest.
    func releaseAfterPointer() {
        guard !down.subtracting(locked).isEmpty else { return }
        let expected = revision, deadline = ProcessInfo.processInfo.systemUptime + 1
        func check() {
            guard revision == expected else { return }
            if henge_vm_pen_idle() != 0 || ProcessInfo.processInfo.systemUptime >= deadline { releaseOneShot() }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { check() } }
        }
        check()
    }

    func releaseOneShot() { update { $0.releaseOneShot() } }
    func releaseAll() { update { $0.releaseAll() } }
}

/// The keys an on-screen keyboard doesn't have, in the slot above it.
struct ModifierRow: View {
    let hide: () -> Void
    @ObservedObject private var sticky = StickyKeys.shared

    var body: some View {
        HStack(spacing: 5) {
            HeldKey(label: "esc", code: Keys.escape)
            HeldKey(label: "tab", code: Keys.tab)
            modifier("⌃", Keys.control, "Control")
            modifier("⌥", Keys.option, "Option")
            modifier("⌘", Keys.command, "Command")
            HeldKey(label: "←", code: Keys.left)
            HeldKey(label: "↑", code: Keys.up)
            HeldKey(label: "↓", code: Keys.down)
            HeldKey(label: "→", code: Keys.right)
            Button(action: hide) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Desk.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Desk.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .accessibilityLabel("Hide keyboard")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(height: 56)
    }

    private func modifier(_ symbol: String, _ code: UInt16, _ name: String) -> some View {
        let on = sticky.down.contains(code)
        return Button {
            sticky.toggle(code)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Color.white : Desk.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(on ? Desk.accent : Desk.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .accessibilityLabel(name)
    }
}

/// A key that goes down when touched and up when let go, so holding it repeats as on a Mac.
private struct HeldKey: View {
    let label: String
    let code: UInt16
    @State private var down = false

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Desk.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(down ? Desk.accent : Desk.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !down else { return }
                        down = true
                        henge_vm_key(code, 1)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .onEnded { _ in
                        down = false
                        henge_vm_key(code, 0)
                        StickyKeys.shared.releaseOneShot()
                    }
            )
            .accessibilityLabel(label)
    }
}
