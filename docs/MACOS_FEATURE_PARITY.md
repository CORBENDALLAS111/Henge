# macOS compatibility and Sidecar parity

Audit date: 2026-11-22. This is a source and automated-test audit, **not a physical iPad certification**. “Implemented” describes a code path; it does not imply that every macOS application accepts the device or that Apple services authenticate.

## Baseline and dependencies

Main is `7f130f2c6aca25943b65f15534b5a5a3696e206a` (PR #4). Development baseline is `7bf9e1aed07c3897bb431da12fc720de1e2ae48e`, the latest compatible combined branch. New work is stacked on that baseline in `feat/macos-parity`; no experimental branch has been merged into main by this audit.

| PR | Head / base | Latest head | Latest IPA CI | Relationship |
|---|---|---|---|---|
| [#5](https://github.com/CORBENDALLAS111/Henge/pull/5) | fix/ventura-gpu-followup → main | e79ae78 | [passed](https://github.com/CORBENDALLAS111/Henge/actions/runs/44434244370) | Already an ancestor of the selected baseline; do not apply twice |
| [#6](https://github.com/CORBENDALLAS111/Henge/pull/6) | feat/absolute-touch-pencil → main | 06a2982 | [passed](https://github.com/CORBENDALLAS111/Henge/actions/runs/44550358593) | Absolute pen/device foundation |
| [#7](https://github.com/CORBENDALLAS111/Henge/pull/7) | feat/ventura-apple-account → #6 | 486bb40 | [passed](https://github.com/CORBENDALLAS111/Henge/actions/runs/44556315485) | Account experiment; remains opt-in |
| [#8](https://github.com/CORBENDALLAS111/Henge/pull/8) | feat/pencil-file-bridge → #7 | 808b71d | [passed](https://github.com/CORBENDALLAS111/Henge/actions/runs/44575854528) | Pencil, gamepad, file bridges |
| [#9](https://github.com/CORBENDALLAS111/Henge/pull/9) | fix/direct-touch-gestures → #8 | c91fa11 | [passed](https://github.com/CORBENDALLAS111/Henge/actions/runs/44769521035) | Contact/click/gesture arbitration |
| [#10](https://github.com/CORBENDALLAS111/Henge/pull/10) | fix/apple-account-compatibility → #9 | 7bf9e1a | [passed](https://github.com/CORBENDALLAS111/Henge/actions/runs/45070202487) | Natural scroll, tablet queue, diagnostics, graphics retries |

All six PRs were open drafts at audit time. Their green checks are evidence of compilation and fixtures, not six independent compatible feature sets. Main's merge-head run was skipped by the workflow's commit-message filter; the preceding PR #4 build passed. The macOS desktop HID fixture explicitly **skipped** when the runner could not create an IOHIDUserDevice. USB transport tests passed; actual driver/tablet acceptance remains unverified.

## Reading the matrices

Status: **I** implemented; **P** partial/experimental; **M** missing; **R** restricted by platform or requiring a different architecture; **—** not applicable. Ownership: **G** guest macOS/application; **H** iOS host; **V** emulator/virtual device; **A** guest agent; **S** Apple/platform service. Complexity is an estimate, not a delivery promise: S ≈ 1–2 engineer days, M ≈ 3–7 days, L = weeks, XL = substantial device/driver/architecture project. Priorities P0/P1/P2 follow input/graphics, integration, then optional optimization.

Native macOS columns assume compatible Apple hardware and applications. Sidecar is a companion display for an actual Mac: its macOS applications and services run on that Mac. They are not provided by an iPad emulator. Apple documents the current sidebar, Pencil and Touch Bar behavior in the [Sidecar guide](https://support.apple.com/en-us/102597); the [iPadOS 27 guide](https://support.apple.com/guide/ipad/use-your-ipad-as-a-second-display-ipad2b1aa3be/27/ipados/27) describes current device-dependent touch support. Do not project iPadOS 27 behavior onto every older Sidecar combination.

| Capability | Native Apple Silicon Mac | Sidecar / supported iPadOS 27 combination | Henge main | Combined development baseline |
|---|---|---|---|---|
| macOS applications, windows, text editing | I, guest OS itself | I, on companion Mac | P, emulated CPU/PVG limitations | P, same architecture |
| Finger absolute positioning / direct clicks | No built-in touchscreen | Device/version dependent | M, Direct Touch falls back to trackpad | I, absolute USB HID pen + mouse clicks |
| One-finger natural scrolling | Trackpad uses two fingers | Version/interaction dependent | M | I, virtual MT2 gesture with inertia |
| Two-finger scroll, pinch; three/four-finger gestures | I, trackpad and settings | P, supported gesture set | I, MT2 trackpad | I, MT2; Direct Touch gates stationary taps |
| Pencil pressure / tilt / roll / hover / eraser | External tablet required | P, hardware/app dependent | M | P, generic digitizer reports; guest app acceptance unverified |
| Pencil double-tap / squeeze | External device dependent | Hardware/version dependent | M | P, host actions; no universal guest Pencil Pro API |
| Sidebar modifiers, keyboard, undo, Dock/menu shortcuts | Keyboard/UI | I | M | M at baseline; see implementation record below |
| Virtual Touch Bar | No built-in Touch Bar on current Apple Silicon models | I, supported companion Mac apps | M | M, no guest export/control mechanism |
| Metal / compositing / Retina | I, native drivers | I, companion Mac renders | P, PVG replay | P, same replay with extra diagnostics/retries |
| Camera / microphone input | I | Companion Mac's devices, not general iPad passthrough | M | M |
| Audio output / headset routing | I | Mac output routing | I | I, iPad route picker; no microphone return path |
| Physical keyboard, mouse, trackpad | I | I, host OS routing | I | P, reset/ownership improvements; device QA pending |
| Game controller | I, app dependent | Companion Mac devices | M | I, one generic USB gamepad bridge |
| Files / folder sharing | I | Mac files and platform integrations | P, WebDAV/agent | P, Files importer/exporter + WebDAV |
| Clipboard | Text, rich text, images | Platform clipboard / Continuity | P, text only | P, text only |
| Network / Bonjour / IPv6 | I | Companion Mac networking | P, IPv4 NAT + discovery | P, IPv4 NAT + discovery |
| Apple Account / App Store | S, supported hardware identity | Companion Mac account | Fails reported login | P, opt-in identity experiment; login not verified |
| Suspend / restart / sequential sessions | I | Companion Mac lifecycle | P | P, normal sequential VM teardown supported; installer exception |
| Concurrent independent VMs | Supported host virtualization configurations | Not a VM manager | M | R, process-global VM state |

## Input, interaction and display inventory

| Feature / owner | Status | Source | Limitation / next work | Priority / complexity | Verification |
|---|---|---|---|---|---|
| Absolute Direct Touch / H,V | I | [DirectTouch.swift](../ios/Henge/DirectTouch.swift), [absolute_pen.h](../devices/absolute_pen.h) | Image-local mapping; independent standard mouse click collection. Actual app hit targets still need device QA | P0 / M | HID packet and coordinate fixtures; user reported baseline taps working |
| Single/double click, context menu, drag/resize/selection / G,H,V | P | [DirectContactGesture.swift](../ios/Henge/DirectContactGesture.swift) | Hold/move distinguishes drag, secondary click and scroll. Guest window hit-testing belongs to macOS; app-specific timing remains | P0 / M | Contact timing fixtures; acceptance tests below |
| One-finger scroll and inertia / H,V,G | I | [OneFingerScroll.swift](../ios/Henge/OneFingerScroll.swift), DirectTouch.swift | Synthetic MT2 two-contact gesture; pause before moving permits drag. iOS-style decay is an approximation, not Apple's private curve | P0 / M | Time-step/velocity/stop/cancel fixtures; Safari physical QA pending |
| Two-finger scroll/pinch/right click / H,V,G | P | [Trackpad.swift](../ios/Henge/Trackpad.swift), [DirectMultiTouchGate.swift](../ios/Henge/DirectMultiTouchGate.swift) | Trackpad gestures use guest preferences. Baseline deliberately suppresses stationary Direct Touch two-finger taps; optional context tap can coexist with prior behavior | P0 / M | Gate/trackpad logic, guest behavior pending |
| Mission Control, Spaces, App Exposé / G,V | P | Trackpad.swift, [xhci.c](../devices/xhci.c) | Native MT2 reports, enabled/configured in guest; system-reserved iPadOS gestures may intercept | P0 / M | Packet path implemented; physical three/four-finger tests pending |
| Instant white icon-only mode toggle / H | I | [SessionView.swift](../ios/Henge/SessionView.swift) | Mode transition resets contact state | P0 / S | SDK compilation; mid-session device QA pending |
| Pencil drawing, pressure/tilt/twist, eraser/invert / H,V,G | P | [AbsolutePenSample.swift](../ios/Henge/AbsolutePenSample.swift), [PencilProximity.swift](../ios/Henge/PencilProximity.swift), absolute_pen.h | Generic HID digitizer, not Sidecar's proprietary tablet. Graphics mode preserves down and curved stroke samples; bounded queue may coalesce on saturation | P0 / L | Sanitized production xHCI fixtures, sample/proximity tests; desktop driver fixture skipped |
| Hover, coalesced/estimated samples / H,V | P | DirectTouch.swift, PencilProximity.swift | Compatible Pencil/iPad only. Estimate updates are scoped to active contact; stale updates rejected | P0 / M | Token/estimate fixtures; real hover pending |
| Pencil double-tap/squeeze / H | P | DirectTouch.swift | Configured host actions can select eraser/context behavior; no claimed native macOS squeeze/roll tool API. See [Pencil input](https://developer.apple.com/documentation/uikit/handling-input-from-apple-pencil) and [Pencil Pro APIs](https://developer.apple.com/videos/play/wwdc2024/10214/) | P0 / M | Availability-guarded SDK compile; Pencil Pro required |
| Mouse ownership and disconnect reset / H,V | P | [Hardware.swift](../ios/Henge/Hardware.swift), [PhysicalMouseButtons.swift](../ios/Henge/PhysicalMouseButtons.swift) | Conservative arbitration pauses Direct Touch/Pencil while a physical mouse is connected. Truly concurrent independent pointer tools are missing | P0 / L | Button transitions/generation tests; hot-plug QA pending |
| Physical keys / modifier shortcuts / H,V | P | Hardware.swift, [Input.swift](../ios/Henge/Input.swift) | HID usages and repeat forwarded. iPadOS-reserved combinations cannot always be captured. Ownership of screen/physical modifiers needs independent tracking | P0 / M | Ordering logic reviewed; regression tests added with implementation |
| Rotation, zoom, Retina, custom resolution / H,V | P | [GuestResolution.swift](../ios/Henge/GuestResolution.swift), [BootDisplay.swift](../ios/Henge/BootDisplay.swift), [DisplayRouter.swift](../ios/Henge/DisplayRouter.swift) | Source-pixel metadata preserved; external device surface is trackpad. Resolution/rotation under live input needs hardware QA | P0 / M | Resolution, display target/router/scene fixtures |
| External display + keyboard/mouse / H | P | [ExternalScreenPlan.swift](../ios/Henge/ExternalScreenPlan.swift), [LegacyExternalDisplay.swift](../ios/Henge/LegacyExternalDisplay.swift) | iOS 27 path and older deployment path; preserve custom resolution | P0 / M | SDK and routing fixtures; actual monitor required |
| Per-VM input/display preferences / H | P | [Machines.swift](../ios/Henge/Machines.swift), [MacSettingsView.swift](../ios/Henge/MacSettingsView.swift) | Display is per VM; existing touch mode/scroll preferences are global. New sidebar preferences can be per VM without changing guest metadata | P1 / M | Display validation tests; profile round trips needed for new settings |

## Graphics compatibility inventory

Rendering remains guest PVG → [pvg_lite.c](../devices/pvg_lite.c) → [pvg_metal.m](../devices/pvg_metal.m) → Metal. No color substitution, screen overlay, or forced full redraw is a fix.

| Feature / owner | Status | Limitation / source | Priority / complexity | Verification |
|---|---|---|---|---|
| Ventura magenta rectangles / V,G | P, unresolved | Diagnostic command/function/pipeline metadata exists; no failing guest trace establishing one root cause. [Capture procedure](ventura-gpu-diagnostics.md) | P0 / L | No claim of a physical visual fix |
| Missing render/compute functions and pipelines / V | P | Bounded retry/cache invalidation for late guest definitions. Unsupported operations still need correct Metal translation, not silent omission | P0 / L | [test_pvg_retry.c](../tests/test_pvg_retry.c); native renderer fixtures |
| Surface/texture aliases, backing changes, synchronization / V | P | Full-byte backing hashes and identity, bounds checks, fence/lifecycle cleanup in pvg_metal.m. New guest formats require implementations | P0 / L | [test_pvg_surfaces.m](../tests/test_pvg_surfaces.m), [test_pvg_lifecycle.m](../tests/test_pvg_lifecycle.m) |
| Transparency, shadows, window compositing / G,V | P | Guest WindowServer composes through supported PVG ops; incomplete shaders/formats may still fail | P0 / L | Fixtures do not establish application parity |
| Frame pacing, tearing, cursor / H,V | P | CAMetalLayer presentation and separate guest cursor; reset/generation logic prevents stale display owners. No measured physical refresh/latency baseline | P0 / M | Display/lifecycle fixtures; hardware timing pending |
| Retina sharpness / H,V | P | Native pixel dimensions and cursor scaling retained; zoom interpolation/display choice can affect appearance | P0 / M | Resolution fixtures; real display inspection pending |
| Dynamic wallpapers / Dock icons / G,V | P, known limitations | Upstream reports animation stalls and missing Ventura Calendar Dock date; CPU video decoding costly. A still-wallpaper tip is not a graphics fix | P1 / L | No new validation |

| Application | Existing evidence | Current acceptance status |
|---|---|---|
| Safari | Historical README report; scroll/input fixtures | Page rendering, text selection and sustained inertial scroll require device test |
| Finder | Historical README report | Window move/resize, file copy and context menus require device test |
| System Settings | Historical report; user could open settings | Scrolling and formerly purple panels require device test |
| Chrome | Historical README report | Browser UI, WebGL and scrolling unverified in this build |
| VS Code | Historical README report | Editor, menus and Electron compositing unverified in this build |
| Electron / Codex | Reported magenta rectangles | Unresolved; collect bounded diagnostics, reproduce before claiming fix |
| Graphics-heavy apps | Shader/surface fixtures only | No app suite or graphics benchmark on physical iPad |

## Peripherals, files, network and services

| Feature / owner | Status | Source / concrete boundary | Priority / complexity | Verification |
|---|---|---|---|---|
| iPad virtual webcam / H,V | M | [VolumeClicks.swift](../ios/Henge/VolumeClicks.swift) captures only to intercept volume buttons; frames are discarded. Need AVFoundation capture + virtual UVC device + guest negotiation, not just permission | P1 / XL | No guest camera |
| Microphone / bidirectional audio / H,V | M | [virtio_snd.c](../devices/virtio_snd.c) has no capture stream; RX buffers fail. Add capture/ring buffers/device negotiation before claiming input | P1 / L | Output tests do not validate input |
| Speaker, Bluetooth/USB headset output / H,V | I | [AudioOutputPicker.swift](../ios/Henge/AudioOutputPicker.swift), [audio_mac.c](../host/audio_mac.c); follows iPadOS route | P1 / M | SDK compile; route changes and latency need device test |
| Controller axes/buttons / H,V | I | [HardwareGamepad.swift](../ios/Henge/HardwareGamepad.swift), [usb_gamepad.h](../devices/usb_gamepad.h) | P1 / M | Generic device/mapping/disconnect fixtures; no rumble or multiple-controller claim |
| Files import/export, external storage via Files / H | I | [SharedFileStore.swift](../ios/Henge/SharedFileStore.swift), [FileTransfers.swift](../ios/Henge/FileTransfers.swift): security scopes, provider coordination, staged copies, collision naming, cancellation | P1 / M | Filesystem fixtures; provider interruption/hardware test pending |
| Folder sharing / H,V,A | P | [share.c](../host/share.c), [henge-agent.m](../tools/henge-agent.m), [Sharing.swift](../ios/Henge/Sharing.swift): private host WebDAV mount | P1 / M | HTTP/files fixtures; mount/reconnect and guest agent must be exercised |
| Native drag/drop / H,A | P | Drop imports to Shared Files; not arbitrary macOS file promises in both directions. Transfer progress currently item-level, not byte-level resumable streaming | P1 / L | Files fixtures; real Files provider QA pending |
| Clipboard text / H,A | I | share.c and henge-agent.m; protected pasteboard types excluded | P1 / S | Text protocol implemented; background/reconnect QA pending |
| Clipboard rich text/images / H,A | M | Existing protocol is text-only; requires typed bounded binary transport and pasteboard conversion | P1 / M | No implementation |
| IPv4 internet / V | I | [net_slirp.c](../host/net_slirp.c), NAT, guest DHCP/DNS; host does not bypass guest TLS | P1 / M | DNS/lifecycle tests; guest connectivity QA pending |
| Bonjour / local discovery / H,V | P | DNSService discovery proxy for selected service types and .local addresses; not general multicast bridging | P1 / M | [test_mdns_proxy.c](../tests/test_mdns_proxy.c), LocalNetworkStatus.swift; permission/LAN test pending |
| IPv6 / V | M | libslirp IPv6 is not enabled/configured; discovering an AAAA record does not supply IPv6 routing | P1 / L | No IPv6 end-to-end test |
| Inbound / configurable forwarding / H,V | P | HV_NET_FWD supports one loopback TCP debug mapping; no per-VM UI, LAN listener or general UDP forwarding | P1 / M | Not a user-ready LAN service bridge |
| USB/Bluetooth raw peripherals / H,V | R/P | iPadOS exposes protocol-specific APIs, not arbitrary desktop USB/radio access. Supported accessory/[DriverKit](https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados) entitlement paths need separate bridges; no generic passthrough | P1 / XL | No raw passthrough claim |
| Printers/scanners/MIDI / H,V,A | M | Host AirPrint UI is not a guest printer. CoreMIDI/allowed accessories could feed an explicit virtual-device/agent protocol | P1 / L–XL | No guest bridge |
| iPhone/iPad discovery / H,V | P | Bonjour can advertise/discover selected services; USB pairing/restore libraries are not general Finder device passthrough | P1 / L | No guest Finder device acceptance |
| AirDrop/Handoff/Universal Clipboard / S | M/R | No verified Continuity identity/radio/protocol integration; ordinary clipboard/network bridges do not implement these services | P2 / XL | Unsupported claim explicitly avoided |
| Host battery/thermal diagnostics / H | P | SessionView.swift displays thermal state, JIT activity/network frames; no guest battery device or battery diagnostic UI | P1 / M | Runtime readings require device |
| Media/function keys / H,V,G | P | HardwareKeys forwards available HID key usages; reserved system keys may be consumed by iPadOS. Consumer-page media forwarding is incomplete | P1 / M | Hardware keyboard QA required |

## Apple services and data safety

See [apple-services.md](apple-services.md), [ventura-account-experiment.md](ventura-account-experiment.md), [AppleAccountSupport.swift](../ios/Henge/AppleAccountSupport.swift), [ExistingAccountProfile.swift](../ios/Henge/ExistingAccountProfile.swift), and [check-apple-services.sh](../tools/check-apple-services.sh).

The opt-in profiles are exact-build compatibility experiments, not Apple-supported identity provisioning. They preserve disks, VM UUID/ECID/seed, auxiliary data and guest Keychains; profile installation is atomic and bound to the VM. Do not regenerate identifiers or wipe account data to make an authentication error disappear. Synthetic serial/MLB values and scoped kernel compatibility policies do not supply Secure Enclave provisioning.

Apple's [supported iCloud VM mechanism](https://developer.apple.com/documentation/virtualization/using-icloud-with-macos-virtual-machines) requires supported host provisioning and new compatible macOS VMs. Henge's iOS JIT/device emulation is not that host. Apple's [VM service limits](https://support.apple.com/en-us/120468) also exclude some media services. Guest Ventura sign-in remains **unverified/failing as reported**, even when MFA is accepted. No security validation is disabled by this audit and no account experiment is merged automatically.

The optional diagnostic prints fixed allowlisted error domains/codes/counts and profile flags, not raw authentication logs, tokens or account names. Four Python fixtures check the packaged script. Obtain the actual bounded diagnostic and OS build before attributing login to networking, identity or an account restriction. The audit has no new guest error capture and cannot truthfully name one proven root cause.

## Lifecycle and performance

| Feature / owner | Status | Source / limitation | Priority / complexity | Verification |
|---|---|---|---|---|
| JIT/cache efficiency / V | P | core/ arm64 translator; no replacement architecture. Benchmark cache/memory/thermal before changing policies | P1 / L | Core JIT/MMU/exception fixtures; device performance unmeasured |
| Normal guest shutdown/restart/sequential sessions / H,V | I | [guest-shutdown.md](guest-shutdown.md), host VM lifecycle: drain threads/GPU/network/disks and generation guards | P0 / M | Native VM lifecycle tests; normal guest previously reported upstream, current device QA pending |
| Installer shutdown/reuse / H,V | P | Restore stack can retain long-lived ownership; installer still requires app relaunch | P1 / L | Documented exception; do not claim every session reusable |
| Instant Resume / H,V | P | [InstantResume.swift](../ios/Henge/InstantResume.swift): atomic save, build/VM/CPU/RAM/display identity checks; global default off, disabled for account experiment VMs | P0 / L | Snapshot identity/lifecycle fixtures; interrupted-save/physical resume QA pending |
| Backgrounding / memory pressure / resource cleanup / H,V | P | SessionView and native teardown/reset guards. iPadOS can kill the app; this is not guaranteed background CPU execution | P0 / L | Automated teardown checks; jetsam/thermal/device soak pending |
| Storage/snapshot crash recovery / H,V | P | Partial-save isolation and explicit errors; no complete snapshot history/transactional disk rollback manager | P1 / L | Disk persistence must be tested with copies; no destructive migration |
| CPU/GPU/RAM diagnostics / H,V | P | JIT blocks/s, thermal/network/session logs; no complete GPU-time, memory-history or power panel | P1 / M | Existing counters only |
| Multiple independent active VMs / H,V | R | Global board, pointer, renderer, audio/network state. Sequential normal boots are supported; simultaneous contexts require a broad ownership refactor | P2 / XL | Intentionally not implemented |

## Acceptance and verification ledger

“Required” means a physical-device test remains. CI on a Mac and simulated HID queues do not establish it.

| Acceptance case | Automated evidence | Physical iPad/iPhone / guest test |
|---|---|---|
| 1. Dock taps without dragging | Stationary click/contact and xHCI report tests | Required, single and double taps at Retina/native/custom sizes |
| 2. Move/resize windows | Hold/drag arbitration and absolute mapping tests | Required, titlebars and small resize handles |
| 3. Select text/context menu | Contact state and secondary click fixtures | Required, Finder/Safari/editor and long press |
| 4. Smooth Safari scroll | Scroll velocity/decay/time-step/cancel fixtures | Required, slow drag, fast flick, pause-to-drag, stop touch |
| 5. Switch input modes live | Reset paths and SDK compile | Required, while dragging/scrolling/keys held |
| 6. Mouse connect/disconnect | Physical button/reset transitions | Required, USB/Bluetooth/trackpad hot-plug |
| 7. Pencil draw/hover/pressure | Pen samples/proximity/real xHCI; desktop HID driver fixture skipped | Required, Pencil Pro hardware and pressure-aware macOS app; inspect tilt/roll/eraser |
| 8. Rotate/change resolution | Display/router/viewport/resolution fixtures | Required, active finger/Pencil, zoom and software keyboard |
| 9. External monitor/keyboard/mouse | External screen routing and SDK checks | Required, iPadOS 27 and older supported device paths |
| 10. No stuck buttons/jumps | Contact cancellation/queue/ownership fixtures | Required, scene loss, modal, hot-plug, sidebar and mixed input |
| 11. Affected Ventura apps | Metal surfaces/pipeline retry/lifecycle fixtures | Required; magenta issue remains unresolved pending guest trace |
| 12. Suspend/resume/restart preserves data | VM lifecycle/snapshot identity fixtures | Required, normal shutdown/restart, interruption and restored guest files; installer exception |

## Implementation record for this audit branch

The audit commit establishes this baseline. Follow-up commits record actual changes and their test results below; planned work is not counted as implemented.

- No guest disk, Keychain, identity or auxiliary storage migration is part of this audit.
- Existing virtual USB descriptors and snapshot ABI are preserved by the intended host-side input/sidebar changes.
- A virtual Touch Bar is deferred: no working supported guest-wide Touch Bar render/input export exists in this tree. AppKit's NSTouchBar API for an app's own UI is not a system-wide remote bridge. Static pretend Touch Bar controls would not satisfy the requirement.

Run the repository's existing standalone Swift, USB/HID, native renderer and VM lifecycle targets through `.github/workflows/build-henge.yml`. New logic should be exercised directly, not solely source-grep assertions. Final build evidence and hardware gaps must accompany the artifact report.
