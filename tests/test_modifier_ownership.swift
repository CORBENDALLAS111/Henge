import Foundation

@main struct ModifierOwnershipTests {
    static func main() {
        var keys = ModifierOwnership()
        let ctrl: UInt16 = 29, shift: UInt16 = 42
        typealias Event = ModifierOwnership.Transition
        precondition(keys.set(ctrl, owner: .physical, down: true) == Event(code: ctrl, down: true))
        precondition(keys.set(ctrl, owner: .physical, down: true) == nil, "repeat must not add an owner")
        precondition(keys.set(ctrl, owner: .sticky, down: true) == nil)
        precondition(keys.release(.sticky).isEmpty, "screen release must preserve physical Control")
        precondition(keys.release(.physical) == [Event(code: ctrl, down: false)])
        precondition(keys.release(.physical).isEmpty, "disconnect/focus reset is idempotent")

        let outer = ModifierOwnership.Owner.shortcut(UUID())
        let inner = ModifierOwnership.Owner.shortcut(UUID())
        precondition(keys.set(shift, owner: outer, down: true) == Event(code: shift, down: true))
        precondition(keys.set(shift, owner: inner, down: true) == nil)
        precondition(keys.release(inner).isEmpty, "nested shifted typing cannot release outer shortcut")
        precondition(keys.release(outer) == [Event(code: shift, down: false)])
        _ = keys.set(ctrl, owner: .sticky, down: true)
        _ = keys.set(ctrl, owner: .physical, down: true)
        precondition(keys.release(.physical).isEmpty, "disconnect preserves a screen-owned key")
        precondition(keys.release(.sticky) == [Event(code: ctrl, down: false)])

        let expected: [UInt16] = [29, 42, 56, 125, 97, 54, 100, 126]
        for i in 0..<8 { precondition(ModifierOwnership.code(forHID: UInt8(0xe0 + i)) == expected[i]) }
        precondition(ModifierOwnership.code(forHID: 0x04) == nil)
        precondition(ModifierOwnership.code(forHID: 0xdf) == nil)
        precondition(ModifierOwnership.code(forHID: 0xe8) == nil)
        _ = keys.set(shift, owner: .physical, down: true)
        _ = keys.set(ctrl, owner: .physical, down: true)
        precondition(keys.release(.physical).map(\.code) == [ctrl, shift])

        var sticky = StickyModifierState()
        sticky.toggle(ctrl); sticky.toggleLock(shift)
        sticky.releaseOneShot()
        precondition(sticky.down == [shift] && sticky.locked == [shift])
        sticky.toggle(ctrl); sticky.toggle(ctrl)
        precondition(sticky.down == [shift])
        sticky.toggle(shift)
        precondition(sticky.down.isEmpty && sticky.locked.isEmpty)
        sticky.toggleLock(ctrl); sticky.toggleLock(ctrl)
        precondition(sticky.down.isEmpty && sticky.locked.isEmpty)
        sticky.toggleLock(ctrl); sticky.toggle(shift); sticky.releaseAll()
        precondition(sticky.down.isEmpty && sticky.locked.isEmpty, "scene loss must clear locks too")
        print("PASS: modifier ownership, nested shortcuts, HID mapping, sticky lock/consume/reset")
    }
}
