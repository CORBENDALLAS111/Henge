# Guest-assisted drag and scroll

This is an **opt-in experimental** extension of Direct Touch, using the existing
guest helper and private host sharing connection. It does not replace the USB
input devices, renderer or emulator. It requires an updated `henge-agent` and
macOS Accessibility permission. Actual Ventura/iPad acceptance remains unverified.

## Enable

1. Install the corresponding new Henge build and start the guest normally.
2. Open Terminal inside macOS. In Henge's Details → Sharing, tap **Type the
   Update Command** (or **Type the Set Up Command**), then press Return in macOS.
   Updating the helper does not reset the VM, disk, identity, account or Keychain.
3. In Touch Controls, enable One-finger scrolling and **Smart drag and scroll
   (guest helper)**. Touch the Mac image. Allow `henge-agent` in the guest's
   System Settings → Privacy & Security → Accessibility when prompted.

If the helper is absent or old, the host uses normal gestures immediately.
Denied permission or an unsupported app also falls back. Tap-then-drag remains
an explicit override, including for text selection and file/image dragging
inside a scrolling area. Pencil and Trackpad mode keep their existing policy.

## What the guest can know

Apple's public [AXUIElementCopyElementAtPosition](https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition)
returns the accessibility object at a top-left screen coordinate. The agent
maps the normalized source-image point to the guest main display's logical
coordinates and inspects a bounded parent chain. Roles are public accessibility
[attributes](https://developer.apple.com/documentation/applicationservices/carbon_accessibility/attributes).

- Slider, scrollbar, splitter, grow handle and Dock-item roles suggest drag.
- A window's exposed title element or bare toolbar background suggests drag.
  A bare resizable window hit within five logical points of its frame suggests
  resize. A button inside a toolbar is not classified as draggable background.
- Scroll-area/web-area ancestry suggests scroll, including editable documents
  inside those containers. Selectable text outside a scroll container suggests
  drag. Explicit tap-then-drag takes precedence over every automatic hint.
- Unknown, incomplete or slow accessibility providers return no hint. Custom
  canvas apps, some Electron/browser content and unexposed titlebar areas cannot
  be classified universally. The helper does not infer semantic draggable file
  icons from arbitrary images or implement an undocumented universal touch API.

Only role identifiers, positions/sizes and capability booleans are inspected.
The helper does not read titles, labels, URLs, field values, selected text or
document contents, and does not execute Accessibility actions or move the mouse.
The host receives only a request ID and one fixed intent code.

## Timing and ownership

`host/share.c` exposes `/.henge/touch-target` exclusively through the existing
guest-private sharing transport. A long poll wakes on a new finger contact;
there is no continuous accessibility-tree scan or screenshot analysis. Old
helpers do not advertise this channel, so they introduce no query delay.

The single-contact mailbox has monotonically increasing IDs, cancellation and a
120 ms lifetime. The UI does not block on guest networking: it briefly defers
only an undecided swipe and replays the latest original motion sample after a
reply or timeout. Stationary taps never wait. Once drag/scroll has begun, a late
reply cannot change it. Scene loss, mode/layout changes, lift and multi-touch
cancel the request. A second VM/session cannot reuse a previous response.

The AX worker is separate from clipboard/focus reporting, uses messaging
timeouts and an 80 ms traversal budget. Under guest load it may miss the host
deadline; correctness then falls back to the existing gestures. Timeout values
need physical-device tuning rather than being presented as measured latency.

## Source and verification

- `tools/henge-agent.m`: public AX hit test, metadata-only traversal and worker.
- `tools/touch-target-policy.h`: shared, testable role precedence policy.
- `host/touch_target.h`, `host/share.c`: bounded mailbox, parser and HTTP channel.
- `ios/Henge/DirectContactGesture.swift`, `DirectTouch.swift`: pending intent,
  nonblocking query polling, original-sample replay and cancellation.
- `tests/test_touch_target.c`: identity, timeout, reset, parser and role cases.
- `tests/test_input_focus.c`: real server long-poll/response integration,
  old-helper fallback, duplicate rejection and session cancellation.
- `tests/test_direct_contact_gesture.swift`: smart drag/scroll, timeout replay,
  late replies, stationary clicks, explicit tap-drag and Pencil isolation.

The existing IPA workflow compiles the macOS helper, runs the tests and verifies
that the packaged helper contains the new channel. Device tests still required:
Ventura System Settings/Safari scroll, window title/border drag, sliders,
splitters, text selection, Retina/custom resolutions, denied permission,
unsupported apps and a busy/slow guest. No physical-device success is claimed.
