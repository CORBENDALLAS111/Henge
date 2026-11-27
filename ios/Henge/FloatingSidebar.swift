import SwiftUI

/// Optional functional controls, floating independently of guest image mapping.
struct FloatingSidebar: View {
    @Binding var preferences: SidebarPreferences
    @Binding var keyboardVisible: Bool
    let size: CGSize
    let insets: EdgeInsets
    let keyboardTop: CGFloat?
    @ObservedObject private var sticky = StickyKeys.shared
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var collapsed = false
    @State private var activity = 0
    @State private var dragStart: Double?

    private struct IdleKey: Equatable {
        let activity: Int
        let enabled: Bool
        let held: Bool
        let voiceOver: Bool
    }

    var body: some View {
        let bottom = max(insets.bottom + 12, keyboardTop.map { size.height - $0 + 12 } ?? 0)
        let place = SidebarPlacement(width: size.width, height: size.height, top: insets.top + 76,
                                     bottom: bottom, leading: insets.leading, trailing: insets.trailing,
                                     preferences: preferences, collapsed: collapsed)
        Group {
            if collapsed {
                Button(action: interact) {
                    Image(systemName: "sidebar.\(preferences.edge == .left ? "left" : "right")")
                        .frame(width: 56, height: 44)
                }
                .accessibilityLabel("Show Mac sidebar")
            } else {
                VStack(spacing: 0) {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption).frame(width: 56, height: 28)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                            interact()
                            if dragStart == nil { dragStart = preferences.position }
                            guard place.travel > 0 else { return }
                            preferences.position = min(max((dragStart ?? 0.5) + value.translation.height / place.travel, 0), 1)
                        }.onEnded { _ in dragStart = nil })
                        .accessibilityLabel("Sidebar position")
                        .accessibilityAdjustableAction { direction in
                            interact()
                            preferences.position = min(max(preferences.position + (direction == .increment ? 0.1 : -0.1), 0), 1)
                        }
                    ScrollView(.vertical) {
                        VStack(spacing: 2) {
                            modifier("⌘", Keys.command, "Command")
                            modifier("⌥", Keys.option, "Option")
                            modifier("⌃", Keys.control, "Control")
                            modifier("⇧", Keys.shift, "Shift")
                            action("escape", "Escape", .escape)
                            Button {
                                interact(); keyboardVisible.toggle()
                            } label: {
                                Image(systemName: keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(keyboardVisible ? "Hide keyboard" : "Show keyboard")
                            action("arrow.uturn.backward", "Undo", .undo)
                            action("arrow.uturn.forward", "Redo", .redo)
                            action("dock.rectangle", "Show or hide Dock", .dock)
                            action("menubar.rectangle", "Focus menu bar", .menuBar)
                        }.padding(.horizontal, 6).padding(.bottom, 6)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .font(.system(size: 20, weight: .medium))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .frame(width: 56, height: place.height)
        .background {
            if reduceTransparency { RoundedRectangle(cornerRadius: 18).fill(Desk.raised) }
        }
        .deskGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(reduceTransparency ? 1 : preferences.normalized().opacity)
        .position(x: place.x, y: place.y)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mac sidebar")
        .task(id: IdleKey(activity: activity, enabled: preferences.autoHide,
                          held: !sticky.down.isEmpty, voiceOver: voiceOver)) {
            guard preferences.autoHide, sticky.down.isEmpty, !voiceOver else { collapsed = false; return }
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            if !Task.isCancelled { collapsed = true }
        }
        .onDisappear { StickyKeys.shared.releaseAll() }
    }

    private func interact() { activity &+= 1; collapsed = false }

    private func modifier(_ symbol: String, _ code: UInt16, _ name: String) -> some View {
        let held = sticky.down.contains(code), locked = sticky.locked.contains(code)
        return Button {
            interact(); sticky.toggle(code)
        } label: {
            Text(symbol).frame(width: 44, height: 44)
                .background(held ? Desk.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomTrailing) {
                    if locked { Image(systemName: "lock.fill").font(.system(size: 9)).padding(3) }
                }
        }
        .contextMenu {
            Button(locked ? "Unlock \(name)" : "Lock \(name)") { interact(); sticky.toggleLock(code) }
        }
        .accessibilityLabel(name)
        .accessibilityValue(locked ? "Locked" : held ? "On for next key or click" : "Off")
        .accessibilityHint("Tap for the next key or click. Use actions to lock.")
        .accessibilityAction(named: locked ? "Unlock" : "Lock") { interact(); sticky.toggleLock(code) }
    }

    private func action(_ icon: String, _ label: String, _ shortcut: SidebarShortcut) -> some View {
        Button {
            interact()
            GuestModifiers.withHeld(shortcut.modifiers) { Keys.press(shortcut.key) }
            StickyKeys.shared.releaseOneShot()
        } label: {
            Image(systemName: icon).frame(width: 44, height: 44)
        }.accessibilityLabel(label)
    }
}

struct SidebarOptions: View {
    @Binding var preferences: SidebarPreferences
    var body: some View {
        Toggle("Show floating sidebar", isOn: $preferences.enabled)
        if preferences.enabled {
            Picker("Side", selection: $preferences.edge) {
                Text("Left").tag(SidebarPreferences.Edge.left)
                Text("Right").tag(SidebarPreferences.Edge.right)
            }
            LabeledContent("Opacity", value: "\(Int(preferences.opacity * 100))%")
            Slider(value: $preferences.opacity, in: 0.55...1)
                .accessibilityLabel("Sidebar opacity")
            Toggle("Auto-hide after five seconds", isOn: $preferences.autoHide)
            Text("Drag the handle to move the sidebar. Tap a modifier for the next key or click; touch and hold for Lock. Locked modifiers stay visible. Menu bar focuses the Mac's menu bar; Escape dismisses menus. Shortcuts follow the Mac's keyboard settings.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
