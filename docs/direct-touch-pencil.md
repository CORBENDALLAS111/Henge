# Experimental absolute touch and Apple Pencil

The previous safety build intentionally mapped the saved `direct` choice to
Trackpad. This branch restores a separate Direct Touch surface over the Mac's
display, using a new standard USB HID Pen/Stylus on xHCI port 3. It never steers
the relative VirtIO mouse using a guest cursor-feedback loop. The keyboard on
port 1 and Magic Trackpad 2 on port 2 keep their existing descriptors and paths.
The xHCI USB 2 supported-protocol capability now advertises a port **count**, not
a port bitmask (the distinction matters when adding the third port).

## Input behavior

- Display-local coordinates map to HID 0…32767 on each axis, independently of
  custom guest resolution, Retina scaling and macOS mouse acceleration. The
  surface follows the actual displayed image, including zoom/cropping; automatic
  cursor-follow panning pauses in Direct Touch to keep that mapping stable.
- Finger tap: a complete left click at touch-down, emitted on lift. Movement
  under 10 view points is jitter, not drag. Two taps produce two click pairs.
  Moving at least 10 points starts a drag at the original object. Holding still
  for 550 ms opens its context menu once; further motion cannot start a drag.
  Two-finger taps do not click. Native trackpad gestures start only after 8
  points of movement, preventing both the legacy explicit secondary click and
  the guest's own tap recognizer from interpreting a stationary two-finger tap.
  Four-finger taps still reveal controls without forwarding a guest tap.
- Pencil tap: left click on lift; moving 4 points starts a drag with precise,
  coalesced pressure/tilt/roll samples. Holding still for 450 ms then lifting
  sends two complete left clicks. No click is sent by that hold while the tip
  remains down, so holding then moving can still drag. Hover positions the
  cursor without pressing. Finger touches are rejected during Pencil activity.
- Direct finger mode hides the composited guest arrow and shows a 36-point
  contact ring only while touching. Pencil proximity, Trackpad, a physical mouse
  or external display restores the guest arrow. This is host presentation state,
  separate from the guest's cursor visibility and snapshot contents.
- Short primary/secondary clicks use a standard USB Mouse collection, separate
  from digitizer contact. The digitizer payload keeps Tip Switch/Button 1 for
  pressure-bearing drags. Report ID 1 carries the 13-byte digitizer payload
  (14 bytes on wire); report ID 2 carries buttons plus zero relative X/Y
  (4 bytes). A mouse-only report cannot simultaneously send a tablet-hover
  button=0 event. The shared queue sends absolute hover before button-down,
  allows at least 16 ms for positioning, and preserves button edges for 50 ms.
  No relative displacement is used for steering. Cancellation and overflow
  release both mouse and pen at the last delivered position.
  A clean shutdown/cold boot is required to enumerate the revised descriptor.
  The preceding digitizer-only approach still failed the user's stationary
  Launchpad taps despite passing transport tests; the new desktop path needs
  its own runtime acceptance.
- Double-tap and Pencil Pro squeeze respect the user's preferred Pencil action:
  eraser/previous-tool switches the HID inverted-stylus state; palette actions
  map to a context click at the supplied hover pose or a recent hover location.
  Ignore and system-shortcut preferences do not generate guest clicks. Actions
  during a stroke are ignored. These are generic tablet events; each Mac app
  decides whether to use pressure, tilt, rotation and eraser identity. A Mac app's
  proprietary drawing-tool palette cannot be controlled through standard HID.
- Connecting a physical mouse pauses direct touch, Pencil and touchscreen
  trackpad input. Switching modes, backgrounding, cancellation and ownership
  changes and view resizing discard queued motion and release contact **at the last position
  delivered to the guest**, then leave proximity. Up is sent while still in
  range because macOS does not dispatch absolute pointer edges outside range.
- The bounded queue preserves button/proximity transitions while coalescing
  motion. Overflow cancels the contact instead of losing an up transition.
  The full-speed pen endpoint delivers at most one report per advertised 1 ms
  interval. A quick tap's down/up/leave must not drain into the same controller
  pass merely because the guest posted multiple receive buffers. No sleeps are
  added to the CPU/input thread; pending reports use the regular device poll.
  USB endpoint interruption queues release; USB device reset discards old state
  and readiness. Only a configured guest driver posting a full input transfer
  enables absolute input. There is no relative-pointer positioning fallback.

The session's hiding control bar now shows **Touch** or **Trackpad** and offers
both methods in a native picker. An absent saved preference defaults to Direct
Touch; existing explicit choices remain selected. External displays keep
trackpad control. Select Trackpad if the guest does not accept the new device or positioning is
incorrect. External display mode continues to use the iOS screen as a trackpad;
the app cannot directly touch an image shown only on the external display.

## Upgrade and diagnostics

Shut down macOS cleanly **before installing this build**, then start it normally.
The additional USB device changes the snapshot ABI; an Instant Resume image from
the previous build is incompatible. Disk, auxiliary storage, VM identity, custom
resolution and external-display settings are not recreated by this change.

Bounded `xhci: absolute pen` messages report guest IN-endpoint readiness, the
first twelve report deliveries (report ID, flags and inter-report time only) and up to four queue overflows. They contain no
coordinates, pressure samples, account details or credentials. A readiness log
proves that USB transfers were posted, not that the guest cursor behaves correctly.

The choice of HID path follows Apple's open-source
[IOHIDEventDriver](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDEventDriver.cpp)
(`handleDigitizerTransducerReport`) and
[IOHIDEventService](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDEventService.cpp)
(tablet plus absolute-pointer dispatch). This source review does not substitute
for running Ventura's actual driver.

## Verification boundary

Automated checks exercise the production xHCI controller against guest RAM:
descriptors, USB port enumeration capability, driver readiness, report contents,
button edges, motion coalescing, cancel at delivered position, overflow release,
endpoint interruption, unconfiguration and reset. Swift mapping tests cover
coordinates, out-of-bounds/nonfinite input, pressure, tilt and barrel roll. Full
SDK compilation checks Pencil APIs with the existing iOS 17 deployment target.

The interrupt-interval regression failed on the previous controller: one poll
completed all four queued contact reports at once. A deterministic monotonic
clock now checks the 999,999 ns/1,000,000 ns boundary, repeated polls without time
advancing, eight short taps queued while the guest stalls, and a backwards host
clock after snapshot restore. This confirms the transport fix; it does not prove
that it explains every missed click in the user's guest applications.

The desktop-click transport fixture additionally checks two stationary left
clicks and a distinct right-click, zero relative motion, zero digitizer contact
for those clicks, report IDs/GET_REPORT lengths, position-before-click pacing,
button release after cancellation and mouse queue overflow. It passes ASan/UBSan.
`test_desktop_hid.m` attempts the real macOS HID-to-CGEvent path through
IOHIDUserDevice on the CI Mac. It fails on missing or misplaced desktop click
edges, but reports a distinct skip when virtual-HID/event-tap permissions are
unavailable. Such a skip is not a successful driver test, and even a pass on the
runner is not Ventura/iPad acceptance.

**No iPad/Pencil Pro or running Ventura guest is attached to this environment.**
Guest driver binding, absolute-position calibration, clicking, long presses,
window/icon dragging, text selection, multi-finger scroll, zoom, rotation,
Pencil hover/pressure/tilt/roll, double-tap/squeeze and switching to/from a physical
mouse still need on-device verification. The new path remains experimental.


Pencil now also overlays the Mac image in Trackpad mode while finger coordinates
retain the existing trackpad rectangle. Hover/contact ordering, current-sample
corrections and post-lift proximity lifetime are described and tested in
[pencil-devices-files.md](pencil-devices-files.md). This build adds a separate
USB gamepad on port 4; it does not share the pointing collections.

Gesture reference: [Windows App touch and pen](https://learn.microsoft.com/en-us/windows-app/input-keyboard-mouse-touch-pen?tabs=ios-ipados).
Henge follows direct-position taps and one-finger hold for context menus; Pencil
hold-to-double-click is an additional desktop shortcut requested for this fork.
