import Foundation
import SwiftUI
import UIKit

enum TouchInputSafety {
    static let reset = Notification.Name("henge.input.reset")
    static let directDescription = "Experimental absolute touch: tap where to click, or hold and move to drag/select. Two fingers use Mac trackpad gestures. Pencil Pro adds hover, pressure, tilt and barrel roll; double-tap switches eraser and squeeze opens a context menu, according to Pencil settings. Disconnect a physical mouse to use direct input. After updating Henge, shut down and start the Mac once."
}

struct DirectTouchSurface: UIViewRepresentable {
    let isActive: Bool
    func makeUIView(context: Context) -> Surface { Surface() }
    func updateUIView(_ view: Surface, context: Context) { view.setActive(isActive) }
    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.reset() }

    final class Surface: UIView, UIPencilInteractionDelegate, UIPointerInteractionDelegate {
        private var activeInput = false
        private var primary: UITouch?
        private var fingers = Set<UITouch>()
        private var multi = false
        private var startPoint = CGPoint.zero
        private var lastPoint = CGPoint.zero
        private var pendingDown: DispatchWorkItem?
        private var contact = false
        private var eraser = false
        private var lastHover: CGPoint?
        private var lastHoverTime: TimeInterval = 0
        private var lastAction: TimeInterval = 0
        private var observer: NSObjectProtocol?
        private let gestures = Trackpad.Surface()
        private let status = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
            gestures.isUserInteractionEnabled = false
            addSubview(gestures)
            status.textColor = .secondaryLabel
            status.font = .systemFont(ofSize: 12)
            status.textAlignment = .center
            status.numberOfLines = 2
            status.isUserInteractionEnabled = false
            addSubview(status)
            let pencilInteraction = UIPencilInteraction()
            pencilInteraction.delegate = self
            addInteraction(pencilInteraction)
            addInteraction(UIPointerInteraction(delegate: self))
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
            hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            hover.cancelsTouchesInView = false
            addGestureRecognizer(hover)
            observer = NotificationCenter.default.addObserver(forName: TouchInputSafety.reset, object: nil, queue: .main) { [weak self] _ in self?.reset() }
        }
        required init?(coder: NSCoder) { fatalError("Created in code") }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) }; pendingDown?.cancel() }
        override func layoutSubviews() {
            super.layoutSubviews()
            gestures.frame = bounds
            status.frame = CGRect(x: 8, y: max(bounds.height - 48, 0), width: max(bounds.width - 16, 0), height: 40)
        }
        private var usable: Bool { activeInput && !HardwareMouse.shared.hasMouse && henge_vm_pen_ready() != 0 }
        func setActive(_ active: Bool) {
            if !active { reset() }
            activeInput = active
            isUserInteractionEnabled = active
            updateStatus()
        }
        private func updateStatus() {
            status.text = HardwareMouse.shared.hasMouse ? "Direct Touch paused: physical mouse connected"
                : henge_vm_pen_ready() == 0 ? "Waiting for the Mac USB pen driver. Trackpad remains available."
                : eraser ? "Apple Pencil: eraser" : nil
        }
        func reset() {
            pendingDown?.cancel(); pendingDown = nil
            henge_vm_pen_cancel()
            gestures.reset()
            primary = nil; fingers.removeAll(); multi = false; contact = false
            lastHover = nil; lastHoverTime = 0
            updateStatus()
        }
        func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? { .hidden() }

        @discardableResult private func send(_ point: CGPoint, pressure: CGFloat = 0, altitude: CGFloat = .pi / 2,
                                            azimuth: CGFloat = 0, roll: CGFloat = 0, flags: Int32) -> Bool {
            guard usable else { return false }
            let s = AbsolutePenSample(point: point, size: bounds.size, pressure: pressure, altitude: altitude,
                                      azimuth: azimuth, roll: roll, flags: flags)
            if henge_vm_pen(s.x, s.y, s.pressure, s.tiltX, s.tiltY, s.twist, s.flags) != 0 {
                reset()
                HengeLog.log("input", "absolute pen: queue unavailable; contact cancelled")
                return false
            }
            return true
        }
        private func pencil(_ touch: UITouch, down: Bool) {
            lastHoverTime = ProcessInfo.processInfo.systemUptime
            var roll: CGFloat = 0
            if #available(iOS 17.5, *) { roll = touch.rollAngle }
            let pressure = touch.maximumPossibleForce > 0 ? touch.force / touch.maximumPossibleForce : 1
            send(touch.preciseLocation(in: self), pressure: down ? pressure : 0, altitude: touch.altitudeAngle,
                 azimuth: touch.azimuthAngle(in: self), roll: roll, flags: 4 | (down ? 1 : 0) | (eraser ? 8 : 0))
        }
        private func pressFinger() {
            pendingDown?.cancel(); pendingDown = nil
            guard primary != nil, !multi, usable else { return }
            contact = send(startPoint, pressure: 1, flags: 5)
            if contact && lastPoint != startPoint { send(lastPoint, pressure: 1, flags: 5) }
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard usable else { updateStatus(); return }
            if let pen = touches.first(where: { $0.type == .pencil }) {
                reset(); primary = pen
                pencil(pen, down: true); contact = primary != nil
                return
            }
            guard primary?.type != .pencil else { return } // palm rejection
            guard ProcessInfo.processInfo.systemUptime - lastHoverTime > 0.25 else { return }
            let direct = Set(touches.filter { $0.type == .direct })
            guard !direct.isEmpty else { return }
            fingers.formUnion(direct)
            if fingers.count >= 2 {
                if !multi {
                    pendingDown?.cancel(); pendingDown = nil
                    henge_vm_pen_cancel(); contact = false; primary = nil; multi = true
                    gestures.touchesBegan(fingers, with: event)
                } else { gestures.touchesBegan(direct, with: event) }
                return
            }
            guard let first = direct.first else { return }
            primary = first; startPoint = first.location(in: self); lastPoint = startPoint
            send(startPoint, flags: 4)
            let work = DispatchWorkItem { [weak self] in self?.pressFinger() }
            pendingDown = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard usable else { reset(); return }
            if multi { gestures.touchesMoved(touches, with: event); return }
            guard let primary, touches.contains(primary) else { return }
            if primary.type == .pencil {
                for sample in event?.coalescedTouches(for: primary) ?? [primary] { pencil(sample, down: true) }
            } else {
                lastPoint = primary.location(in: self)
                if contact { send(lastPoint, pressure: 1, flags: 5) }
            }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            if multi {
                gestures.touchesEnded(touches, with: event)
                fingers.subtract(touches)
                if fingers.isEmpty { multi = false }
                return
            }
            guard let t = primary, touches.contains(t) else { fingers.subtract(touches); return }
            if usable {
                if t.type == .pencil { pencil(t, down: false) }
                else {
                    lastPoint = t.location(in: self)
                    if !contact { pressFinger() }
                    if contact { send(lastPoint, pressure: 1, flags: 5); send(lastPoint, flags: 4) }
                }
                // Up must be delivered in range before proximity leave, since
                // macOS does not dispatch pointer edges outside pen range.
                send(t.location(in: self), flags: 0)
            }
            pendingDown?.cancel(); pendingDown = nil
            primary = nil; contact = false; fingers.subtract(touches)
            StickyKeys.shared.releaseAll()
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { reset() }

        @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
            guard usable, primary == nil, !multi else { return }
            switch recognizer.state {
            case .began, .changed:
                let p = recognizer.location(in: self)
                guard bounds.contains(p) else { return }
                lastHover = p; lastHoverTime = ProcessInfo.processInfo.systemUptime
                var roll: CGFloat = 0
                if #available(iOS 17.5, *) { roll = recognizer.rollAngle }
                send(p, altitude: recognizer.altitudeAngle, azimuth: recognizer.azimuthAngle(in: self), roll: roll, flags: 4 | (eraser ? 8 : 0))
            case .ended, .cancelled:
                henge_vm_pen_cancel(); lastHover = nil
            default: break
            }
        }
        private func action(_ preferred: UIPencilPreferredAction, at point: CGPoint?) {
            guard usable, primary == nil, !multi, preferred != .ignore else { return }
            if #available(iOS 17.5, *), preferred == .runSystemShortcut { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastAction > 0.15 else { return }
            lastAction = now
            if preferred == .switchEraser || preferred == .switchPrevious {
                eraser.toggle()
                henge_vm_pen_cancel() // new proximity event updates the guest's pen/eraser identity
                if let p = point ?? lastHover { send(p, flags: 4 | (eraser ? 8 : 0)) }
                updateStatus()
                return
            }
            guard let p = point ?? (now - lastHoverTime < 1 ? lastHover : nil), bounds.contains(p) else { return }
            send(p, flags: 6); send(p, flags: 4)
        }
        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) { action(UIPencilInteraction.preferredTapAction, at: nil) }
        @available(iOS 17.5, *)
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            action(UIPencilInteraction.preferredTapAction, at: tap.hoverPose?.location)
        }
        @available(iOS 17.5, *)
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            if squeeze.phase == .ended { action(UIPencilInteraction.preferredSqueezeAction, at: squeeze.hoverPose?.location) }
        }
    }
}
