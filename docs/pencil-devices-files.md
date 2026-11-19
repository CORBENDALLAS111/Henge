# Pencil, connected accessories and file drag-and-drop

This extends the Ventura account experiment in PR #7. **Apple Account sign-in
and App Store downloads remain unverified.** The experimental mode is available
only when creating a separate Ventura 13.6 (22G120) VM; it does not convert an
existing VM. See [the account experiment](ventura-account-experiment.md).

## Pencil on the Mac image

Pencil works on the displayed image in both Trackpad and Direct Touch modes.
Fingers keep the existing Trackpad geometry in Trackpad mode. Pen coordinates
use the image rectangle within the input view, including letterboxing and zoom
cropping; proximity pauses automatic cursor-follow panning. External-display
mode continues using the iOS screen as the trackpad.

The USB pen sends hover/in-range, tip-down/up, normalized pressure, altitude/
azimuth-derived tilt and Pencil Pro barrel roll. Coalesced samples retain their
order; estimated-property updates are applied only to the most recent active
sample, so late corrections cannot move a stroke backwards or reactivate it.
Double-tap/squeeze retain the preferred-action/eraser/context-menu behavior.

UIKit can end hover at contact and resume it after lift. Hover end now emits an
ordered proximity leave instead of purging the native queue. Tip-up stays in
range; a 60 ms, generation-checked grace period permits hover to resume, then
leaves if it does not. Reset, a new stroke or a new hover invalidates the timeout.
Starting a normal Pencil contact also preserves queued releases; cancellation
is reserved for taking ownership from an active finger/gesture or a lifecycle reset.
This removes a concrete queue-cancellation hazard; it does not establish the
cause of every missed click reported by the user.

This is generic HID tablet input, not Apple's proprietary Sidecar implementation.
Each Mac app decides which tablet features to consume; hover distance, tool
palettes and Apple-specific drawing integration are not emulated. A connected
physical mouse still pauses touchscreen/Pencil input to avoid competing pointers.
Pencil hardware behavior, drawing latency and guest-app compatibility need iPad
verification.

## Bluetooth and other paired accessories

Pair accessories in **iPadOS Settings**. Public GameController/UIKit APIs forward
keyboard and mouse input through the existing virtual keyboard/mouse. Keyboard
disconnect also releases pending HID keys and sticky modifiers.

The first supported extended/micro game controller is exposed as a **generic
USB HID gamepad on xHCI port 4**, independent of keyboard, mouse and pen. It sends
16 button bits, an eight-way hat, two signed sticks and two unipolar triggers.
A/B/X/Y use bits 0–3, shoulders 4–5, Options/Menu 6–7, stick clicks 8–9 and Home
10 when iPadOS delivers it. Sticks use a small rescaled dead zone to suppress
neutral drift. No device identifier or input-value stream is logged.

Reports preserve button/hat edges and axis neutral/sign transitions, coalesce
motion, and respect the advertised 4 ms service interval. Overflow queues neutral
and rejects held controls until neutral returns. Undersized guest buffers do not
consume an input sample. Disconnect, background/modal input suspension, VM pause,
stop and resume release controls. The VM gate is checked under the queue mutex;
a late producer or USB reset cannot reopen input while the VM is paused. Polling
current host values also restores input after guest USB reconfiguration; unchanged
snapshots do not wake the emulated CPU.

The Details panel provides a forwarding switch, readiness status and the system
audio-output picker. Guest audio continues through its existing virtual sound
card and the iPadOS playback route, including paired Bluetooth audio where the
system permits it. Audio routing and real controllers have not been tested here.
Mac games using proprietary controller protocols may ignore a generic HID pad.
Guest controller vibration, motion/touchpad sensors and Bluetooth microphone
capture are not added.

**This is not raw Bluetooth passthrough.** Core Bluetooth exposes application
GATT services, not unrestricted ownership of iPadOS's HCI controller, pairing
keys or all system-managed profiles. No synthetic Bluetooth adapter, private API,
new Bluetooth entitlement or automatic device scan is added. Generic pairing
inside guest Bluetooth Settings and arbitrary BLE/Classic devices remain
unavailable. A particular BLE accessory would require an explicitly implemented
GATT protocol proxy and a guest client; an unrestricted hardware backend would
require a platform that actually grants controller/USB ownership.

## Files in both directions

Use the **Shared Files** button (or Details → Sharing on compact screens).
Drop files/folders from Files onto Henge or a folder in the panel. Copies appear
in the shared WebDAV volume. In macOS, use the existing `~/Henge` mount, or open
Finder → Go → Connect to Server and enter `http://10.0.2.4/`. That address is the
VM's existing internal share, not an Internet upload.

For macOS → iPadOS, copy files into that guest volume, then drag them from the
panel to Files or another accepting iPad app. Outbound file promises use private
independent temporary copies, rather than exposing a URL that becomes invalid
as soon as the drag callback returns. Incoming provider files are copied before
the provider callback returns; unreadable URL representations can fall back to
a file promise. Files are streamed by filesystem copy, without buffering whole
files into Data. Source files are kept; existing names get a numeric suffix.

The panel can browse only Shared. Copying into an ancestor/self, path/name
escapes, reserved server names, symbolic links and special files are rejected.
Failures do not replace an existing destination. Exported snapshots live in the
app's private temporary directory and may be reclaimed by the OS. There is no
automatic guest paste, file execution, account-log upload or permission grant.

This provides drag-and-drop **through the shared folder**, not a continuous
Finder drag into an arbitrary guest window/iPad app across two operating systems.
That would require a separate guest drag-session protocol and application
integration. Real iPad/File Provider/cloud-provider transfers need runtime tests.

## Verification

The portable production-controller tests cover the four-port capability, USB
gamepad descriptor/report contents, clamps, pacing, edge coalescing, neutral
release, overflow, undersized buffers, endpoint interruption and reset. Gamepad
and pen tests pass locally under ASan/UBSan. Swift tests cover frame mapping,
Pencil proximity/correction lifetime, gamepad normalization and file copy/path/
provider-snapshot invariants. CI also compiles against the full iOS SDK and runs
the existing display, input, native VM/DNS/GPU lifecycle and complete IPA/TIPA build.
A build/test pass is not Pencil, Bluetooth, file-drag or account runtime proof.

Shut down macOS cleanly before updating and boot normally. Adding the fourth USB
device changes the snapshot ABI; old Instant Resume saves cannot be used. Existing
disks, auxiliary storage, identity/configuration and Custom Resolution are kept.
