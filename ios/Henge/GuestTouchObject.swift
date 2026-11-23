import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A fresh, metadata-only description of the object hit by one guest query.
/// Raw values are the versioned host/touch_target.h protocol, never AX strings.
struct GuestTouchObject: Equatable {
    enum Kind: Int32 {
        case unknown = 0, window, resize, scroll, slider, scrollbar, splitter
        case textField, textArea, button, toggle, link, item, text
    }
    struct Capabilities: OptionSet, Equatable {
        let rawValue: UInt32
        static let drag = Self(rawValue: 1)
        static let scroll = Self(rawValue: 2)
        static let editable = Self(rawValue: 4)
        static let selectable = Self(rawValue: 8)
        static let press = Self(rawValue: 16)
        static let disabled = Self(rawValue: 32)
        static let horizontal = Self(rawValue: 64)
        static let vertical = Self(rawValue: 128)
        static let editabilityKnown = Self(rawValue: 256)
    }
    let kind: Kind
    let capabilities: Capabilities
    let bounds: CGRect

    init?(kind: Int32, capabilities: UInt32, bounds: CGRect) {
        guard let type = Kind(rawValue: kind), capabilities <= 511,
              bounds.origin.x.isFinite, bounds.origin.y.isFinite, bounds.width.isFinite, bounds.height.isFinite,
              bounds.minX >= 0, bounds.minY >= 0, bounds.size.width >= 0, bounds.size.height >= 0,
              bounds.maxX <= 1.000000001, bounds.maxY <= 1.000000001 else { return nil }
        let c = Capabilities(rawValue: capabilities)
        let field = type == .textField || type == .textArea
        guard !c.contains(.editable) || (field && c.contains(.editabilityKnown)),
              !c.contains(.editabilityKnown) || field,
              !c.contains(.disabled) || c.intersection([.drag, .editable, .press]).isEmpty,
              !c.isSuperset(of: [.horizontal, .vertical]) else { return nil }
        if !c.intersection([.horizontal, .vertical]).isEmpty {
            guard [.slider, .scrollbar, .splitter].contains(type) else { return nil }
        }
        self.kind = type; self.capabilities = c; self.bounds = bounds
    }

    /// nil means the provider couldn't tell. It must not be treated as readonly.
    var keyboardEditable: Bool? {
        if capabilities.contains(.disabled) { return false }
        if kind == .unknown { return nil }
        if kind == .textField || kind == .textArea {
            return capabilities.contains(.editabilityKnown) ? capabilities.contains(.editable) : nil
        }
        return false
    }
    var preciseDrag: Bool {
        capabilities.contains(.drag) && [.slider, .scrollbar, .splitter, .resize].contains(kind)
    }
    var isolatedPress: Bool {
        capabilities.contains(.press) && !capabilities.contains(.scroll) && [.button, .toggle, .link].contains(kind)
    }
    func frame(in image: CGRect) -> CGRect {
        CGRect(x: image.minX + bounds.minX * image.width, y: image.minY + bounds.minY * image.height,
               width: bounds.width * image.width, height: bounds.height * image.height)
    }
}
