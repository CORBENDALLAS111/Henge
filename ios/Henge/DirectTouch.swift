import SwiftUI
import UIKit
import QuartzCore

/// Direct, screen-relative control for the macOS guest. Separate from the
/// Magic Trackpad surface: one finger acts on the item under it, while
/// multi-finger gestures go through the guest's native trackpad driver.
///
/// Henge's virtual mouse is relative, not a touchscreen digitizer. We read
/// the actual guest cursor position and correct towards the touch target
/// over multiple frames, delaying clicks until the cursor reaches it.
struct DirectTouchSurface: UIViewRepresentable {
    let guestWidth: Int
    let guestHeight: Int
    let isActive: Bool

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.guestSize = CGSize(width: guestWidth, height: guestHeight)
        view.isUserInteractionEnabled = isActive
        return view
    }

    func updateUIView(_ view: Surface, context: Context) {
        view.guestSize = CGSize(width: guestWidth, height: guestHeight)
        if !isActive { view.reset() }
        view.isUserInteractionEnabled = isActive
    }

    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.reset() }

    final class Surface: UIView, UIPointerInteractionDelegate {
        var guestSize = CGSize(width: 1920, height: 1080)

        private static let dragThreshold: CGFloat = 9
        private static let cursorTolerance: CGFloat = 7
        private static let holdDelay: CFTimeInterval = 0.38
        private static let tapMaxDuration: CFTimeInterval = 0.35
        private static let sensorW = 8134.0
        private static let sensorH = 5206.0

        private var active = Set<UITouch>()
        private var primary: UITouch?
        private var startTime: CFTimeInterval = 0
        private var startScreen = CGPoint.zero
        private var startGuest = CGPoint.zero
        private var latestGuest = CGPoint.zero
        private var travelled: CGFloat = 0
        private var dragRequested = false
        private var buttonHeld = false
        private var pendingEnd = false
        private var deadline: CFTimeInterval = 0
        private var pendingClick: Int32?
        private var clickGuest = CGPoint.zero
        private var queuedClicks: [(Int32, CGPoint)] = []

        private var multi = false
        private var ids: [UITouch: Int32] = [:]
        private var mostFingers = 0
        private var gestureTravel: CGFloat = 0
        private var gestureStarted: CFTimeInterval = 0
        private var gestureGuest = CGPoint.zero
        private var gestureCancelled = false
        private var displayLink: CADisplayLink?
        private var lastMove: CFTimeInterval = 0
        // In direct mode the guest applies mouse acceleration. Adapt the relative
        // movement size from the actual cursor displacement to converge quickly
        // even on a 4K guest, while preventing high-gain overshoots.
        private var calibratedGain: CGFloat = 1.8
        private var previousCursor: CGPoint?
        private var previousCommand = CGPoint.zero
        private var lastError = CGPoint.zero
        private var lastMoveTime: CFTimeInterval = 0
        private let feedback = UIImpactFeedbackGenerator(style: .light)

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = true
            isOpaque = false
            addInteraction(UIPointerInteraction(delegate: self))
        }

        required init?(coder: NSCoder) { fatalError("Created in code") }

        func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
            .hidden()
        }

        private func guestPoint(_ p: CGPoint) -> CGPoint {
            let x = min(max(p.x / max(bounds.width, 1), 0), 1)
            let y = min(max(p.y / max(bounds.height, 1), 0), 1)
            return CGPoint(x: (guestSize.width - 1) * x, y: (guestSize.height - 1) * y)
        }

        private func sensorPoint(_ t: UITouch) -> (Int32, Int32) {
            let w = max(Double(bounds.width), 1), h = max(Double(bounds.height), 1)
            let p = t.location(in: self)
            let scale = min(Self.sensorW / w, Self.sensorH / h)
            let x = (Double(p.x) - w / 2) * scale + Self.sensorW / 2
            let y = (Double(p.y) - h / 2) * scale + Self.sensorH / 2
            return (Int32(min(max(x, 0), Self.sensorW)), Int32(min(max(y, 0), Self.sensorH)))
        }

        private static func ms(_ timestamp: TimeInterval) -> UInt32 {
            UInt32(truncatingIfNeeded: Int(timestamp * 1000))
        }

        private func startLink() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFramesPerSecond = 60
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        private func releaseButton() {
            if buttonHeld { henge_vm_mouse_button(0, 0); buttonHeld = false }
        }

        func reset() {
            releaseButton()
            let ts = Self.ms(ProcessInfo.processInfo.systemUptime)
            for id in ids.values { henge_vm_touch(id, 2, 0, 0, ts) }
            if !ids.isEmpty { henge_vm_touch_frame(ts) }
            ids.removeAll()
            active.removeAll()
            primary = nil
            multi = false
            dragRequested = false
            pendingEnd = false
            pendingClick = nil
            queuedClicks.removeAll()
            previousCursor = nil
            previousCommand = .zero
            calibratedGain = 1.8
            stopLink()
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            let down = touches.filter { $0.type == .direct || $0.type == .pencil }
            guard !down.isEmpty else { return }
            for t in down { active.insert(t) }
            if active.count >= 2 {
                if !multi { beginMulti() }
                else { addMulti(Array(down)) }
                return
            }
            guard !multi, let t = active.first else { return }
            // Preserve an earlier click still converging on its target.
            primary = t
            startTime = CACurrentMediaTime()
            startScreen = t.location(in: self)
            startGuest = guestPoint(startScreen)
            latestGuest = startGuest
            travelled = 0
            pendingEnd = false
            dragRequested = false
            feedback.prepare()
            startLink()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            if multi {
                let ts = Self.ms(event?.timestamp ?? touches.first?.timestamp ?? 0)
                var sent = false
                for t in touches {
                    guard let id = ids[t] else { continue }
                    let p = t.location(in: self), previous = t.previousLocation(in: self)
                    gestureTravel += hypot(p.x - previous.x, p.y - previous.y)
                    let (x, y) = sensorPoint(t)
                    henge_vm_touch(id, 1, x, y, ts)
                    sent = true
                }
                if sent { henge_vm_touch_frame(ts) }
                return
            }
            guard let t = primary, touches.contains(t) else { return }
            let p = t.location(in: self)
            travelled = max(travelled, hypot(p.x - startScreen.x, p.y - startScreen.y))
            latestGuest = guestPoint(p)
            if travelled >= Self.dragThreshold { dragRequested = true }
            startLink()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            finishTouches(touches, cancelled: false)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            finishTouches(touches, cancelled: true)
        }

        private func finishTouches(_ touches: Set<UITouch>, cancelled: Bool) {
            if multi {
                gestureCancelled = gestureCancelled || cancelled
                let ts = Self.ms(touches.map(\.timestamp).max() ?? ProcessInfo.processInfo.systemUptime)
                for t in touches {
                    guard let id = ids.removeValue(forKey: t) else { continue }
                    henge_vm_touch(id, 2, 0, 0, ts)
                }
                henge_vm_touch_frame(ts)
                active.subtract(touches)
                guard active.isEmpty else { return }
                let quick = CACurrentMediaTime() - gestureStarted <= Self.tapMaxDuration
                if !gestureCancelled && quick && gestureTravel < 18 {
                    if mostFingers == 2 { queueClick(1, at: gestureGuest) }
                    if mostFingers >= 4 {
                        NotificationCenter.default.post(name: Trackpad.revealTap, object: nil)
                    }
                }
                multi = false
                ids.removeAll()
                mostFingers = 0
                StickyKeys.shared.releaseAll()
                if pendingClick == nil { stopLink() }
                return
            }
            guard let t = primary, touches.contains(t) else { active.subtract(touches); return }
            active.subtract(touches)
            primary = nil
            if cancelled {
                releaseButton()
                pendingClick = nil
                queuedClicks.removeAll()
                dragRequested = false
                pendingEnd = false
                stopLink()
            } else if dragRequested {
                pendingEnd = true
                // Finish even a fast swipe: align to its start, press, travel to
                // the last finger position and release. Previously rapid drags
                // were dropped whenever the cursor had not caught up at lift.
                deadline = CACurrentMediaTime() + 1.2
                startLink()
            } else {
                queueClick(0, at: startGuest)
            }
            StickyKeys.shared.releaseAll()
        }

        private func queueClick(_ button: Int32, at guest: CGPoint) {
            dragRequested = false
            pendingEnd = false
            if pendingClick != nil {
                if queuedClicks.count < 4 { queuedClicks.append((button, guest)) }
                return
            }
            pendingClick = button
            clickGuest = guest
            deadline = CACurrentMediaTime() + 0.7
            startLink()
        }

        private func advanceClick(_ now: CFTimeInterval) {
            guard !queuedClicks.isEmpty else { return }
            let (button, point) = queuedClicks.removeFirst()
            pendingClick = button
            clickGuest = point
            deadline = now + 0.7
        }

        private func beginMulti() {
            releaseButton()
            pendingClick = nil
            queuedClicks.removeAll()
            primary = nil
            dragRequested = false
            pendingEnd = false
            multi = true
            gestureCancelled = false
            gestureStarted = CACurrentMediaTime()
            gestureTravel = 0
            mostFingers = active.count
            let points = active.map { $0.location(in: self) }
            let centre = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                                 y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
            gestureGuest = guestPoint(centre)
            ids.removeAll()
            addMulti(Array(active))
            stopLink()
        }

        private func addMulti(_ touches: [UITouch]) {
            let ts = Self.ms(touches.map(\.timestamp).max() ?? ProcessInfo.processInfo.systemUptime)
            for t in touches where ids[t] == nil {
                guard let id = (1...5).first(where: { !ids.values.contains(Int32($0)) }) else { break }
                ids[t] = Int32(id)
                let (x, y) = sensorPoint(t)
                henge_vm_touch(Int32(id), 0, x, y, ts)
            }
            henge_vm_touch_frame(ts)
            mostFingers = max(mostFingers, ids.count)
        }

        @objc private func tick(_ link: CADisplayLink) {
            let now = CACurrentMediaTime()
            if primary != nil && !dragRequested && travelled < Self.dragThreshold && now - startTime >= Self.holdDelay {
                dragRequested = true
            }
            if now > deadline && (pendingClick != nil || pendingEnd) {
                // A missed target is safer than an accidental click on the wrong Mac control.
                if pendingClick != nil { HengeLog.log("input", "direct touch: guest cursor did not reach tap target") }
                pendingClick = nil
                advanceClick(now)
                if pendingEnd { releaseButton(); pendingEnd = false; dragRequested = false }
            }

            let target: CGPoint
            if pendingClick != nil { target = clickGuest }
            else if dragRequested { target = buttonHeld ? latestGuest : startGuest }
            else if primary != nil { target = startGuest }
            else { stopLink(); return }

            var x: Int32 = 0, y: Int32 = 0
            guard henge_vm_pointer(&x, &y) == 0 else { return }
            let cursor = CGPoint(x: CGFloat(x), y: CGFloat(y))
            if let previousCursor, now - lastMoveTime > 0.025 {
                let observed = hypot(cursor.x - previousCursor.x, cursor.y - previousCursor.y)
                let requested = hypot(previousCommand.x, previousCommand.y)
                // Ignore old samples (different input owners, delayed guest
                // commits, and gestures) when estimating the mouse gain.
                if requested >= 4 && observed >= 1 && observed < requested * 16 {
                    let sample = min(max(observed / requested, 0.3), 8)
                    calibratedGain = calibratedGain * 0.78 + sample * 0.22
                }
                self.previousCursor = nil
            }
            let dx = target.x - cursor.x, dy = target.y - cursor.y
            if hypot(dx, dy) <= Self.cursorTolerance {
                if let button = pendingClick {
                    henge_vm_mouse_button(button, 1)
                    henge_vm_mouse_button(button, 0)
                    pendingClick = nil
                    feedback.impactOccurred()
                    advanceClick(now)
                }
                if dragRequested && !buttonHeld &&
                   hypot(startGuest.x - cursor.x, startGuest.y - cursor.y) <= Self.cursorTolerance {
                    henge_vm_mouse_button(0, 1)
                    buttonHeld = true
                    feedback.impactOccurred()
                }
                if pendingEnd && buttonHeld &&
                   hypot(latestGuest.x - cursor.x, latestGuest.y - cursor.y) <= Self.cursorTolerance {
                    releaseButton()
                    pendingEnd = false
                    dragRequested = false
                }
                if primary == nil && pendingClick == nil && !dragRequested { stopLink() }
                return
            }
            // Closed-loop cursor positioning. High distances use larger coarse
            // moves, small distances use precise corrections. This is mouse
            // emulation, not a real absolute HID digitizer, so we wait for the
            // guest cursor feedback and learn its acceleration scale.
            guard now - lastMove >= 0.025 else { return }
            lastMove = now
            let distance = hypot(dx, dy)
            let cap: CGFloat = distance > 900 ? 450 : distance > 250 ? 240 : 80
            let factor: CGFloat = distance > 250 ? 0.85 : 0.65
            let gain = max(calibratedGain, 0.3)
            func component(_ d: CGFloat) -> Int32 {
                guard abs(d) > Self.cursorTolerance else { return 0 }
                let value = min(max((d / gain * factor).rounded(), -cap), cap)
                return Int32(value == 0 ? (d > 0 ? 1 : -1) : value)
            }
            let mx = component(dx), my = component(dy)
            if mx != 0 || my != 0 {
                previousCursor = cursor
                previousCommand = CGPoint(x: CGFloat(mx), y: CGFloat(my))
                lastMoveTime = now
                lastError = CGPoint(x: dx, y: dy)
                henge_vm_mouse_move(mx, my)
            }
        }
    }
}
