# Experimental absolute touch and Apple Pencil

## Scroll and drag together

With one-finger scrolling on, a single swipe scrolls. To drag a window, icon or
selection immediately, **tap once, then touch the same object again and move
without lifting the second touch**. The second touch starts a drag after the
normal movement threshold, even when moving immediately. Two stationary taps
still send two clicks. The second touch must begin within 350 ms of the first
tap's release and within 24 host points. Scene/mode/layout changes and
multi-touch cancel this history. Pausing 220 ms before moving also permits drag;
holding still for 550 ms keeps the existing context menu behavior. Pencil and
Trackpad modes retain their existing drag policy.

## Optional two-finger context tap and sidebar

Details / Settings → Touch Controls → **Two-finger tap for context menu** is
off by default to preserve existing stationary-tap behavior. When enabled, a
quick stationary pair right-clicks at its midpoint. A scroll, drag, third finger,
long press, cancelled gesture, movement on lift or a touch outside the Mac image
cannot finish as a context click. Moving pairs still use native guest gestures.

Details → **Floating Sidebar** enables actual Mac modifier keys, Escape,
keyboard visibility, Undo/Redo, Dock toggle and menu-bar focus. Tap a modifier
for the next key/click or long-press it to Lock. Locks clear when the input
session is hidden or loses ownership. Side/position/opacity/auto-hide are stored
per VM; guest disks and saved device layouts do not change.

## Graphics tablet mode

**Settings / Details → Touch Controls → Pencil as graphics tablet** defaults on.
Pencil tip-down now starts a pen stroke immediately; stationary dots, pressure
changes and sub-slop movements are forwarded. Holding the tip does not synthesize
a double-click in this mode. Disable the setting to retain desktop Pencil gestures.
Switching mode cancels the current contact before changing policy.

The existing pen channel carries 12-bit pressure, X/Y tilt and barrel rotation
in hundredths of degrees, hover/proximity and the eraser tool. Coalesced UIKit
samples are retained in order while the queue has room; near its bounded capacity
motion coalesces with four slots reserved for contact release/proximity leave.
The eraser descriptor now distinguishes its contact switch from inverted-tool
hover; cancellation clears contact while retaining tool proximity until leave.
The report size and USB endpoint stay the same. Cold boot after updating so
macOS enumerates the revised descriptor.

Apple Pencil double-tap/squeeze continue following system preferences between
strokes: eraser actions switch tools and palette actions produce a guest context
menu. Available force/hover/roll depends on the connected Pencil and iPad.
macOS drawing apps must consume tablet events and enable pressure/tilt/rotation
for the selected brush. This is a standard HID graphics tablet; it does not
implement Apple's private Sidecar transport or its app-specific palettes.

Portable tests cover immediate dots, tiny strokes, pressure/tilt/roll mapping,
sixty retained curved-path samples, bounded backpressure, eraser hover/contact
and cancellation. The optional real-macOS HID test also checks actual tablet
pressure, tilt, rotation and eraser proximity when runner permissions permit it.
A permission skip is not guest validation. Ventura/iPad/Pencil app acceptance
still requires a real device.

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
  Trackpad tap clicks use the same mouse reports without changing the pointer position. No relative displacement is used for steering. Cancellation and overflow
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

The session's hiding control bar has a white icon-only control button. Each tap
switches Direct Touch ↔ Trackpad immediately, with no menu. VoiceOver announces
the selected mode and the next action. An absent saved preference defaults to
Direct Touch; explicit saved choices remain selected. External displays keep
trackpad control and disable this button.

### One-finger scrolling

Use **Settings or Details → Touch Controls → One-finger scrolling**. It
defaults on when no preference has been saved. An explicit saved on/off choice
is preserved. Turn it off to restore immediate one-finger dragging. With it on:

- A quick swipe beyond the existing 10-point slop scrolls.
- Pause at least 220 ms before moving to drag/select instead.
- A stationary 550-ms hold still opens one context menu.
- A tap or two quick taps still produces ordinary primary clicks.
- Pencil pointing and dragging retain their original policy.

A classified swipe becomes two virtual Magic Trackpad contacts (IDs 8/9), not
mouse-wheel ticks. Both contacts move in one frame at each UIKit sample's own
timestamp. A clearly dominant axis locks to prevent sideways drift; diagonal
pans retain both axes. Scaling uses the displayed Mac image, including a zoomed
or keyboard-shifted image, rather than the surrounding touch panel. Movement
beyond the sensor edge is discarded so reversal responds immediately. A pause
of at least 50 ms supplies a stationary frame before release; a continuing
flick releases directly. macOS supplies
acceleration, natural-scroll direction and momentum using its existing trackpad
settings; this does not claim to duplicate the iPhone's exact deceleration curve.
There is no additional host momentum generator to double the guest's inertia.
Source points are bounded to the native sensor range. Cancellation, rotation,
mode changes, backgrounding and transition to real multifinger input release
both virtual contacts. Scroll actions never emit click/auto-keyboard requests.

The native trackpad queue coalesces only repeated motion with matching finger
IDs/contact states and physical-button state. Initial contact transitions remain
ordered, with the newest move and its original timestamp retained. Even a full
edge-filled queue retains the final stop/empty state instead of silently dropping
finger-up reports. Controller tests cover a thousand queued moves and release
under backpressure, alongside the existing stationary click regressions.

The follow-up's standalone Swift emitter/classifier tests pass on Swift 6.2.3
in Swift 5 mode, including diagonal pans, edge reversal and pause/flick release.
Account support/profile persistence tests and the 6,021-check software-identity
suite also pass. These are source-level checks; physical iPad scroll feel and
Apple Account authentication remain separate device acceptance checks.

Select Trackpad if the guest does not accept the absolute device or positioning
is incorrect. On an external display the iOS screen remains a trackpad.

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

The user reported that taps, drag, long-press context menus and custom resolution
work on their existing Ventura after installing b639ca575124. Apple Account/App
Store downloads are still unconfirmed. One-finger scrolling and the revised
icon-only button are new and still require that same on-device acceptance.

**No iPad/Pencil Pro or running Ventura guest is attached to this environment.**
Broader guest driver binding, absolute-position calibration, text selection,
one/multi-finger scroll, zoom, rotation,
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
