import Foundation

/// Compatibility mapping for GameController physical mice/trackpads only.
/// Guest button IDs are 0 = left, 1 = right, 2 = middle; touch controls retain those IDs.
struct PhysicalMouseButtons {
    static let swapKey = "henge.mouse.swapRightAndMiddle"

    /// Captured when the VM session starts, so a held button's release uses the same mapping.
    let swapsRightAndMiddle: Bool
    private(set) var held: Set<Int32> = []
    private var owners: [AnyHashable: Set<Int32>] = [:]

    init(swapsRightAndMiddle: Bool) {
        self.swapsRightAndMiddle = swapsRightAndMiddle
    }

    mutating func event(_ physicalButton: Int32, pressed: Bool, source: AnyHashable = 0) -> Int32? {
        guard (0...2).contains(physicalButton) else { return nil }
        let guestButton = swapsRightAndMiddle && physicalButton != 0 ? 3 - physicalButton : physicalButton
        if pressed {
            owners[source, default: []].insert(guestButton)
            held.insert(guestButton)
        } else {
            guard owners[source]?.contains(guestButton) == true else { return nil }
            owners[source]?.remove(guestButton)
            if owners.values.contains(where: { $0.contains(guestButton) }) { return nil }
            held.remove(guestButton)
        }
        return guestButton
    }

    /// Release all mapped buttons on disconnect or when the VM input session ends.
    mutating func releaseAll() -> [Int32] {
        let releases = held.sorted()
        held.removeAll()
        owners.removeAll()
        return releases
    }

    mutating func disconnect(_ source: AnyHashable) -> [Int32] {
        owners.removeValue(forKey: source)
        let remaining = owners.values.reduce(into: Set<Int32>()) { $0.formUnion($1) }
        let releases = held.subtracting(remaining).sorted()
        held = remaining
        return releases
    }
}
