import Foundation

/// Host-only, per-VM preferences. No guest metadata or snapshot schema changes.
struct SidebarPreferences: Codable, Equatable {
    enum Edge: String, Codable, CaseIterable { case left, right }
    var enabled = false
    var edge = Edge.left
    var position = 0.5
    var opacity = 0.9
    var autoHide = false

    func normalized() -> Self {
        var copy = self
        copy.position = position.isFinite ? min(max(position, 0), 1) : 0.5
        copy.opacity = opacity.isFinite ? min(max(opacity, 0.55), 1) : 0.9
        return copy
    }

    private static func key(_ id: UUID) -> String { "henge.sidebar.\(id.uuidString)" }
    static func load(for id: UUID, defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key(id)),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value.normalized()
    }
    func save(for id: UUID, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(normalized()) else { return }
        defaults.set(data, forKey: Self.key(id))
    }
}

/// Bounds are in host points; the guest viewport is never resized by the panel.
struct SidebarPlacement {
    let x: Double
    let y: Double
    let height: Double
    let travel: Double

    init(width: Double, height: Double, top: Double, bottom: Double,
         leading: Double, trailing: Double, preferences: SidebarPreferences, collapsed: Bool) {
        func finite(_ x: Double) -> Double { x.isFinite ? max(x, 0) : 0 }
        let w = finite(width), h = finite(height)
        let low = min(finite(top), h), high = max(low, h - finite(bottom))
        self.height = min(collapsed ? 44 : 512, high - low)
        travel = max(0, high - low - self.height)
        let p = preferences.normalized()
        y = low + self.height / 2 + travel * p.position
        let left = min(w / 2, finite(leading) + 36)
        let right = max(w / 2, w - finite(trailing) - 36)
        x = p.edge == .left ? left : right
    }
}

/// Linux keyboard codes used by the existing virtual keyboard. These are real
/// guest shortcuts, subject to the user's macOS shortcut configuration.
enum SidebarShortcut: CaseIterable {
    case escape, undo, redo, dock, menuBar
    var key: UInt16 {
        switch self {
        case .escape: return 1
        case .undo, .redo: return 44 // Z
        case .dock: return 32 // D
        case .menuBar: return 60 // F2
        }
    }
    var modifiers: [UInt16] {
        switch self {
        case .escape: return []
        case .undo: return [125]
        case .redo: return [42, 125]
        case .dock: return [56, 125]
        case .menuBar: return [29]
        }
    }
}
