import Foundation
import Combine
import GameController

/// One controller as a generic USB HID gamepad. All entry points, notifications
/// and handlerQueue callbacks are on the main queue, like HardwareMouse.
final class HardwareGamepad: ObservableObject {
    static let shared = HardwareGamepad()
    static let enabledKey = "henge.controller.forward"
    @Published private(set) var status = "No game controller connected"
    private var primary: GCController?
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    private var active = false

    func start() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in self?.select() })
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let removed = note.object as? GCController, removed === self.primary else { return }
            self.detach(); self.select(excluding: removed)
        })
        select()
    }

    func stop() {
        active = false
        detach()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        setStatus("No game controller connected")
    }

    func setActive(_ value: Bool) {
        active = value
        if !value { henge_vm_gamepad_cancel() }
        refresh()
    }

    private func detach() {
        generation &+= 1
        primary?.extendedGamepad?.valueChangedHandler = nil
        primary?.microGamepad?.valueChangedHandler = nil
        primary = nil
        henge_vm_gamepad_cancel()
    }

    private func select(excluding removed: GCController? = nil) {
        guard primary == nil else { return }
        guard let controller = GCController.controllers().first(where: { ($0 !== removed) && ($0.extendedGamepad != nil || $0.microGamepad != nil) }) else {
            setStatus("No game controller connected")
            return
        }
        generation &+= 1
        let token = generation
        primary = controller
        controller.handlerQueue = .main
        controller.extendedGamepad?.valueChangedHandler = { [weak self, weak controller] _, _ in
            guard let self, let controller, token == self.generation, self.primary === controller else { return }
            self.refresh()
        }
        controller.microGamepad?.valueChangedHandler = { [weak self, weak controller] _, _ in
            guard let self, let controller, token == self.generation, self.primary === controller else { return }
            self.refresh()
        }
        refresh()
    }

    private func sample(_ controller: GCController) -> GamepadSample? {
        if let g = controller.extendedGamepad {
            var buttons: UInt16 = 0
            let inputs: [GCControllerButtonInput?] = [g.buttonA, g.buttonB, g.buttonX, g.buttonY,
                g.leftShoulder, g.rightShoulder, g.buttonOptions, g.buttonMenu,
                g.leftThumbstickButton, g.rightThumbstickButton, g.buttonHome]
            for (i, input) in inputs.enumerated() where input?.isPressed == true { buttons |= 1 << i }
            return GamepadSample(buttons: buttons, dpadX: g.dpad.xAxis.value, dpadY: g.dpad.yAxis.value,
                                 leftX: g.leftThumbstick.xAxis.value, leftY: g.leftThumbstick.yAxis.value,
                                 rightX: g.rightThumbstick.xAxis.value, rightY: g.rightThumbstick.yAxis.value,
                                 leftTrigger: g.leftTrigger.value, rightTrigger: g.rightTrigger.value)
        }
        if let g = controller.microGamepad {
            let buttons: UInt16 = (g.buttonA.isPressed ? 1 : 0) | (g.buttonX.isPressed ? 4 : 0) | (g.buttonMenu.isPressed ? 128 : 0)
            return GamepadSample(buttons: buttons, dpadX: g.dpad.xAxis.value, dpadY: g.dpad.yAxis.value)
        }
        return nil
    }

    private func setStatus(_ value: String) { if status != value { status = value } }

    private func refresh() {
        guard let primary else { setStatus("No game controller connected"); return }
        guard active else { setStatus("Controller input paused"); return }
        guard henge_vm_gamepad_ready() != 0 else { setStatus("Waiting for the Mac USB gamepad driver"); return }
        guard let sample = sample(primary) else { return }
        let result = sample.axes.withUnsafeBufferPointer { henge_vm_gamepad(UInt32(sample.buttons), sample.hat, $0.baseAddress) }
        let next = result == 0 ? "Forwarding to Henge USB Gamepad" : "Release the controls to resume input"
        setStatus(next)
    }

    /// Resend current values after guest USB reconfiguration, even without a new
    /// physical event. The native queue deduplicates unchanged snapshots.
    @MainActor func followGuest() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
