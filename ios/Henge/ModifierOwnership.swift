import Foundation

/// The guest sees a key transition only when its first owner presses or its
/// last owner releases. A sidebar tap must not release a physical key.
struct ModifierOwnership {
    enum Owner: Hashable {
        case physical, sticky
        case shortcut(UUID)
    }
    struct Transition: Equatable {
        let code: UInt16
        let down: Bool
    }
    private var owners: [UInt16: Set<Owner>] = [:]

    static func code(forHID usage: UInt8) -> UInt16? {
        let codes: [UInt16] = [29, 42, 56, 125, 97, 54, 100, 126]
        guard (0xe0...0xe7).contains(usage) else { return nil }
        return codes[Int(usage - 0xe0)]
    }

    mutating func set(_ code: UInt16, owner: Owner, down: Bool) -> Transition? {
        var held = owners[code] ?? []
        let wasDown = !held.isEmpty
        if down { held.insert(owner) } else { held.remove(owner) }
        if held.isEmpty { owners.removeValue(forKey: code) } else { owners[code] = held }
        return wasDown == !held.isEmpty ? nil : Transition(code: code, down: !held.isEmpty)
    }

    mutating func release(_ owner: Owner) -> [Transition] {
        // Stable ordering also makes focus-loss releases deterministic.
        owners.keys.sorted().compactMap { set($0, owner: owner, down: false) }
    }
}

/// A tap is consumed by the next key/click; a locked modifier survives until
/// explicitly toggled off or the input session loses ownership.
struct StickyModifierState: Equatable {
    private(set) var down: Set<UInt16> = []
    private(set) var locked: Set<UInt16> = []

    mutating func toggle(_ code: UInt16) {
        if down.remove(code) != nil { locked.remove(code) }
        else { down.insert(code) }
    }
    mutating func toggleLock(_ code: UInt16) {
        if locked.remove(code) != nil { down.remove(code) }
        else { down.insert(code); locked.insert(code) }
    }
    mutating func releaseOneShot() { down = locked }
    mutating func releaseAll() { down.removeAll(); locked.removeAll() }
}
