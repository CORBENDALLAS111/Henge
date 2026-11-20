import Foundation
import SwiftUI
import UIKit

enum TouchInputSafety {
    static let reset = Notification.Name("henge.input.reset")
    static let pencilPresence = Notification.Name("henge.input.pencilPresence")
    static let directDescription = "Direct Touch: tap to click, tap twice to double-click, move to drag, or hold still for a right-click. Two fingers scroll; a two-finger tap does not click. Pencil: tap to click, move to drag, or hold still then lift to double-click. Pencil Pro adds hover, pressure, tilt and barrel roll; double-tap switches eraser and squeeze opens a context menu, according to Pencil settings. Disconnect a physical mouse to use direct input. After updating Henge, shut down and start the Mac once."
}

struct DirectTouchSurface: UIViewRepresentable {
    let isActive: Bool
    var directFingers = true
    var imageFrame: CGRect? = nil
    func makeUIView(context: Context) -> Surface { Surface() }
    func updateUIView(_ view: Surface, context: Context) {
        view.setActive(isActive, directFingers: directFingers)
        view.setImageFrame(imageFrame)
    }
    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.reset() }

    final class Surface: UIView, UIPencilInteractionDelegate, UIPointerInteractionDelegate {
        private var activeInput = false
        private var directFingers = true
        private var proximity = PencilProximity()
        private var displayFrame: CGRect?
        private var imageBounds: CGRect { displayFrame ?? bounds }
        private var pendingLeave: DispatchWorkItem?
        private var pencilPresent = false
        private var primary: UITouch?
        private var fingers = Set<UITouch>()
        private var multi = false
        private var multiGate = DirectMultiTouchGate()
        private var multiOrigins: [UITouch: CGPoint] = [:]
        private var startPoint = CGPoint.zero
        private var lastPoint = CGPoint.zero
        private var pendingDown: DispatchWorkItem?
        private var contact = false
        private var classifier = DirectContactGesture()
        private let touchRing = CAShapeLayer()
        private var eraser = false
        private var lastHover: CGPoint?
        private var lastHoverTime: TimeInterval = 0
        private var lastAction: TimeInterval = 0
        private var previousSize: CGSize?
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
            touchRing.fillColor = UIColor.white.withAlphaComponent(0.12).cgColor
            touchRing.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor
            touchRing.lineWidth = 1.5
            touchRing.isHidden = true
            layer.addSublayer(touchRing)
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
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) }; pendingDown?.cancel(); pendingLeave?.cancel() }
        override func layoutSubviews() {
            super.layoutSubviews()
            if let previousSize, previousSize != bounds.size { reset() }
            previousSize = bounds.size
            gestures.frame = bounds
            status.frame = CGRect(x: max(imageBounds.minX, 0) + 8, y: max(min(imageBounds.maxY, bounds.height) - 48, 0), width: max(min(imageBounds.width, bounds.width) - 16, 0), height: 40)
        }
        func setImageFrame(_ frame: CGRect?) {
            guard displayFrame != frame else { return }
            if let old = displayFrame, let frame, old != frame { reset() }
            displayFrame = frame
            setNeedsLayout()
        }
        private var usable: Bool { activeInput && !HardwareMouse.shared.hasMouse && henge_vm_pen_ready() != 0 }
        func setActive(_ active: Bool, directFingers: Bool) {
            if !active || self.directFingers != directFingers { reset() }
            self.directFingers = directFingers
            gestures.allowsTouchscreenClicks = !directFingers
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
            pendingLeave?.cancel(); pendingLeave = nil
            classifier.reset()
            showTouch(nil)
            proximity.reset()
            setPencilPresent(false)
            henge_vm_pen_cancel()
            gestures.reset()
            primary = nil; fingers.removeAll(); multi = false; contact = false
            multiGate.reset(); multiOrigins.removeAll()
            lastHover = nil; lastHoverTime = 0
            updateStatus()
        }
        func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? { .hidden() }

        @discardableResult private func send(_ point: CGPoint, pressure: CGFloat = 0, altitude: CGFloat = .pi / 2,
                                            azimuth: CGFloat = 0, roll: CGFloat = 0, flags: Int32) -> Bool {
            guard usable else { return false }
            let s = AbsolutePenSample(point: point, imageFrame: imageBounds, pressure: pressure, altitude: altitude,
                                      azimuth: azimuth, roll: roll, flags: flags)
            if henge_vm_pen(s.x, s.y, s.pressure, s.tiltX, s.tiltY, s.twist, s.flags) != 0 {
                reset()
                HengeLog.log("input", "absolute pen: queue unavailable; contact cancelled")
                return false
            }
            return true
        }
        private func setPencilPresent(_ present: Bool) {
            guard present != pencilPresent else { return }
            pencilPresent = present
            // setActive/reset can be called from updateUIView. Notify SwiftUI
            // after that update, rather than mutating view state reentrantly.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: TouchInputSafety.pencilPresence, object: nil, userInfo: ["present": present])
            }
        }
        private func leave(_ point: CGPoint) {
            send(point, flags: 0) // ordered leave; never purge a preceding contact-up
            lastHover = nil
            setPencilPresent(false)
        }
        private func pencil(_ touch: UITouch, down: Bool, correction: Bool = false, at location: CGPoint? = nil) {
            if down && !correction {
                proximity.recordSample(estimate: touch.estimationUpdateIndex?.intValue, timestamp: touch.timestamp)
            }
            lastHoverTime = ProcessInfo.processInfo.systemUptime
            let point = location ?? touch.preciseLocation(in: self)
            lastHover = point
            var roll: CGFloat = 0
            if #available(iOS 17.5, *) { roll = touch.rollAngle }
            let pressure = touch.maximumPossibleForce > 0 ? touch.force / touch.maximumPossibleForce : 1
            send(point, pressure: down ? pressure : 0, altitude: touch.altitudeAngle,
                 azimuth: touch.azimuthAngle(in: self), roll: roll, flags: 4 | (down ? 1 : 0) | (eraser ? 8 : 0))
        }
        private func showTouch(_ point: CGPoint?) {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            touchRing.isHidden = point == nil
            if let point {
                touchRing.path = UIBezierPath(ovalIn: CGRect(x: point.x - 18, y: point.y - 18, width: 36, height: 36)).cgPath
            }
            CATransaction.commit()
        }
        private func perform(_ actions: [DirectContactGesture.Action], pencilTouch: UITouch? = nil) {
            let range: Int32 = 4 | (pencilTouch != nil && eraser ? 8 : 0)
            for action in actions {
                switch action {
                case .down(let p), .move(let p):
                    if let pencilTouch {
                        pencil(pencilTouch, down: true, at: p)
                        contact = primary != nil
                    } else { contact = send(p, pressure: 1, flags: 5) }
                    if !contact { return }
                case .up(let p):
                    send(p, flags: range); contact = false
                case .click(let p, let count, let secondary):
                    // Each complete pair remains in the USB queue, including fast double-clicks.
                    for _ in 0..<count {
                        guard send(p, flags: range | Int32(secondary ? HENGE_PEN_DESKTOP_RIGHT : HENGE_PEN_DESKTOP_LEFT)),
                              send(p, flags: range | Int32(HENGE_PEN_DESKTOP_UP)) else { return }
                    }
                    if !secondary {
                        NotificationCenter.default.post(name: SessionKeyboard.directTap, object: nil, userInfo: [
                            "x": Double((p.x - imageBounds.minX) / max(imageBounds.width, 1)),
                            "y": Double((p.y - imageBounds.minY) / max(imageBounds.height, 1))])
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
        private func beginMulti(_ touches: Set<UITouch>, event: UIEvent?) {
            multi = true
            if directFingers {
                multiGate.begin(count: fingers.count, time: touches.map(\.timestamp).min() ?? ProcessInfo.processInfo.systemUptime)
                for finger in fingers where multiOrigins[finger] == nil { multiOrigins[finger] = finger.location(in: self) }
                if multiGate.forwarding { gestures.touchesBegan(touches, with: event) }
            } else { gestures.touchesBegan(touches, with: event) }
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard activeInput, !HardwareMouse.shared.hasMouse else { updateStatus(); return }
            if let pen = touches.first(where: { $0.type == .pencil }) {
                guard usable, imageBounds.contains(pen.preciseLocation(in: self)) else { updateStatus(); return }
                // A normal hover -> contact (or quick second stroke) must not
                // purge the preceding tip-up still queued for the guest.
                // Cancel only when taking ownership from an active touch.
                if primary != nil || !fingers.isEmpty || multi { reset() }
                pendingLeave?.cancel(); pendingLeave = nil
                primary = pen
                proximity.beginContact(); setPencilPresent(true)
                startPoint = pen.preciseLocation(in: self)
                classifier.begin(startPoint, tool: .pencil, time: pen.timestamp)
                pencil(pen, down: false)
                return
            }
            guard primary?.type != .pencil, !proximity.isHovering else { return } // palm rejection
            guard ProcessInfo.processInfo.systemUptime - lastHoverTime > 0.25 else { return }
            let direct = Set(touches.filter { $0.type == .direct })
            guard let first = direct.first else { return }
            if !directFingers || multi || (fingers.isEmpty && !imageBounds.contains(first.location(in: self))) {
                fingers.formUnion(direct)
                beginMulti(direct, event: event)
                return
            }
            guard usable else { updateStatus(); return }
            fingers.formUnion(direct)
            if fingers.count >= 2 {
                if !multi {
                    pendingDown?.cancel(); pendingDown = nil
                    henge_vm_pen_cancel(); classifier.reset(); showTouch(nil); contact = false; primary = nil
                    beginMulti(fingers, event: event)
                } else { beginMulti(direct, event: event) }
                return
            }
            primary = first; startPoint = first.location(in: self); lastPoint = startPoint
            classifier.begin(startPoint, tool: .finger, time: first.timestamp)
            showTouch(startPoint)
            send(startPoint, flags: 4)
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.primary != nil, !self.multi else { return }
                self.perform(self.classifier.hold(time: ProcessInfo.processInfo.systemUptime))
            }
            pendingDown = work
            DispatchQueue.main.asyncAfter(deadline: .now() + DirectContactGesture.contextDelay, execute: work)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard activeInput, !HardwareMouse.shared.hasMouse else { reset(); return }
            if multi {
                if !directFingers || multiGate.forwarding { gestures.touchesMoved(touches, with: event) }
                else {
                    let distance = fingers.compactMap { finger -> Double? in
                        guard let origin = multiOrigins[finger] else { return nil }
                        let p = finger.location(in: self)
                        return Double(hypot(p.x - origin.x, p.y - origin.y))
                    }.max() ?? 0
                    if multiGate.move(distance: distance, count: fingers.count) {
                        gestures.touchesBegan(fingers, with: event)
                        gestures.touchesMoved(touches, with: event)
                    }
                }
                return
            }
            guard usable else { reset(); return }
            guard let primary, touches.contains(primary) else { return }
            if primary.type == .pencil {
                for sample in event?.coalescedTouches(for: primary) ?? [primary] {
                    perform(classifier.move(sample.preciseLocation(in: self)), pencilTouch: sample)
                }
            } else {
                lastPoint = primary.location(in: self)
                showTouch(lastPoint)
                perform(classifier.move(lastPoint))
            }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            if multi {
                if !directFingers || multiGate.forwarding { gestures.touchesEnded(touches, with: event) }
                fingers.subtract(touches)
                for touch in touches { multiOrigins.removeValue(forKey: touch) }
                if fingers.isEmpty {
                    if directFingers && multiGate.reveal(time: touches.map(\.timestamp).max() ?? ProcessInfo.processInfo.systemUptime) {
                        NotificationCenter.default.post(name: Trackpad.revealTap, object: nil)
                    }
                    multi = false; multiGate.reset(); multiOrigins.removeAll()
                }
                return
            }
            guard let t = primary, touches.contains(t) else { fingers.subtract(touches); return }
            if usable {
                if t.type == .pencil {
                    perform(classifier.end(t.preciseLocation(in: self), time: t.timestamp), pencilTouch: t)
                    pencil(t, down: false)
                    let token = proximity.endContact(), point = t.preciseLocation(in: self)
                    // UIKit resumes hover after tip-up. Keep the release in range,
                    // then leave only if this exact stroke gets no new hover.
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, self.proximity.expire(token) else { return }
                        self.leave(point)
                    }
                    pendingLeave?.cancel(); pendingLeave = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
                }
                else {
                    lastPoint = t.location(in: self)
                    perform(classifier.end(lastPoint, time: t.timestamp))
                    showTouch(nil)
                }
                // Up must be delivered in range before proximity leave, since
                // macOS does not dispatch pointer edges outside pen range.
                if t.type != .pencil { send(t.location(in: self), flags: 0) }
            }
            pendingDown?.cancel(); pendingDown = nil
            showTouch(nil)
            primary = nil; contact = false; fingers.subtract(touches)
            StickyKeys.shared.releaseAfterPointer()
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { reset() }

        override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
            guard usable, primary?.type == .pencil, contact else { return }
            for sample in touches where sample.type == .pencil {
                if proximity.acceptsCorrection(estimate: sample.estimationUpdateIndex?.intValue, timestamp: sample.timestamp) {
                    pencil(sample, down: true, correction: true)
                }
            }
        }

        @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
            guard usable, primary == nil, !multi else { return }
            switch recognizer.state {
            case .began, .changed:
                let p = recognizer.location(in: self)
                guard imageBounds.contains(p) else {
                    if proximity.hoverEnded(), let lastHover { leave(lastHover) }
                    return
                }
                guard proximity.hoverChanged() else { return }
                pendingLeave?.cancel(); pendingLeave = nil
                setPencilPresent(true)
                lastHover = p; lastHoverTime = ProcessInfo.processInfo.systemUptime
                var roll: CGFloat = 0
                if #available(iOS 17.5, *) { roll = recognizer.rollAngle }
                send(p, altitude: recognizer.altitudeAngle, azimuth: recognizer.azimuthAngle(in: self), roll: roll, flags: 4 | (eraser ? 8 : 0))
            case .ended, .cancelled, .failed:
                if proximity.hoverEnded(), let lastHover { leave(lastHover) }
            default: break
            }
        }
        private func action(_ preferred: UIPencilPreferredAction, at point: CGPoint?) {
            guard usable, primary == nil, !multi, preferred != .ignore else { return }
            if #available(iOS 17.5, *), preferred == .runSystemShortcut { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastAction > 0.15 else { return }
            lastAction = now
            if let point, imageBounds.contains(point), proximity.hoverChanged() {
                pendingLeave?.cancel(); pendingLeave = nil
                lastHover = point; lastHoverTime = now
                setPencilPresent(true)
            }
            if preferred == .switchEraser || preferred == .switchPrevious {
                eraser.toggle()
                if let p = lastHover { send(p, flags: 0) } // ordered proximity change preserves the last stroke-up
                if let p = point ?? lastHover, imageBounds.contains(p) { send(p, flags: 4 | (eraser ? 8 : 0)) }
                updateStatus()
                return
            }
            guard let p = point ?? (now - lastHoverTime < 1 ? lastHover : nil), imageBounds.contains(p) else { return }
            send(p, flags: 4 | Int32(HENGE_PEN_DESKTOP_RIGHT)); send(p, flags: 4 | Int32(HENGE_PEN_DESKTOP_UP))
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
