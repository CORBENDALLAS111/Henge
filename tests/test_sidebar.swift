import Foundation

@main struct SidebarTests {
    static func main() throws {
        let suite = "henge-sidebar-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = UUID(), b = UUID()
        var p = SidebarPreferences()
        precondition(!SidebarPreferences.load(for: a, defaults: defaults).enabled)
        p.enabled = true; p.edge = .right; p.position = 0.75; p.opacity = 0.6; p.autoHide = true
        p.save(for: a, defaults: defaults)
        precondition(SidebarPreferences.load(for: a, defaults: defaults) == p)
        precondition(!SidebarPreferences.load(for: b, defaults: defaults).enabled, "VM settings must be isolated")
        p.position = .nan; p.opacity = -.infinity
        p.save(for: a, defaults: defaults)
        let safe = SidebarPreferences.load(for: a, defaults: defaults)
        precondition(safe.position == 0.5 && safe.opacity == 0.9)
        p.position = -10; p.opacity = 20
        precondition(p.normalized().position == 0 && p.normalized().opacity == 1)
        defaults.set(Data("broken".utf8), forKey: "henge.sidebar.\(a.uuidString)")
        precondition(SidebarPreferences.load(for: a, defaults: defaults) == SidebarPreferences())

        for width in [320.0, 768, 1366] {
            for height in [240.0, 600, 1024] {
                for position in [0.0, 0.5, 1] {
                    p.position = position
                    let layout = SidebarPlacement(width: width, height: height, top: 80, bottom: 30,
                                                  leading: 0, trailing: 0, preferences: p, collapsed: false)
                    precondition(layout.x >= 28 && layout.x <= width - 28)
                    precondition(layout.y - layout.height / 2 >= 80)
                    precondition(layout.y + layout.height / 2 <= height - 30)
                    precondition(layout.height <= 512 && layout.travel >= 0)
                }
            }
        }
        let small = SidebarPlacement(width: 768, height: 1024, top: 80, bottom: 450,
                                     leading: 0, trailing: 0, preferences: p, collapsed: false)
        precondition(small.y + small.height / 2 <= 574, "keyboard must not cover controls")
        let hidden = SidebarPlacement(width: 768, height: 1024, top: 80, bottom: 30,
                                      leading: 0, trailing: 0, preferences: p, collapsed: true)
        precondition(hidden.height == 44 && hidden.travel > small.travel)
        let invalid = SidebarPlacement(width: .nan, height: -.infinity, top: 80, bottom: 0,
                                       leading: 0, trailing: 0, preferences: p, collapsed: false)
        precondition(invalid.x.isFinite && invalid.y.isFinite && invalid.height == 0)
        precondition(SidebarShortcut.undo.key == 44 && SidebarShortcut.undo.modifiers == [125])
        precondition(SidebarShortcut.redo.key == 44 && SidebarShortcut.redo.modifiers == [42, 125])
        precondition(SidebarShortcut.dock.key == 32 && SidebarShortcut.dock.modifiers == [56, 125])
        precondition(SidebarShortcut.menuBar.key == 60 && SidebarShortcut.menuBar.modifiers == [29])
        precondition(SidebarShortcut.escape.key == 1 && SidebarShortcut.escape.modifiers.isEmpty)
        print("PASS: per-VM sidebar storage, corrupt preferences, rotation/keyboard bounds and guest shortcuts")
    }
}
