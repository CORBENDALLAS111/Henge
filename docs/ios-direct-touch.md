# Henge iOS — Custom resolution and Direct Touch

This fork adds two independently selectable features:

## Guest resolution
Open **Macs → [Mac] → Screen → Resolution → Custom**. Enter width and height
and choose **Apply custom resolution**.

- Valid width: 640–7680 px; height: 480–4320 px; budget: at most 8,294,400 pixels.
- Applies at the next **guest Mac boot**, not immediately and not to the iOS panel.
- The selected dimensions live in each \`VirtualMac\` entry in \`machines.json\`.
  The optional \`customResolution\` property preserves compatibility with old saves.
- Other existing presets (Retina, Performance, Fit, 16:9) remain available.

## Touch control
Open **Settings → Touch Controls**, or while a guest is running open
**Details → Touch Controls**. Pick **Trackpad** or **Direct Touch**.

| Gesture on the guest screen | Direct Touch behavior |
|---|---|
| One finger tap | Align guest cursor to touch point, then left-click |
| Two successive taps | Two left-clicks (a double-click if timing permits) |
| One finger move | Align cursor, hold left button, drag the object |
| Hold, then move | Pick up and drag an object |
| Two-finger tap | Secondary (right) click |
| Two-finger pan | Guest Magic Trackpad scroll gesture |
| Two-finger pinch | Guest Magic Trackpad pinch gesture where macOS supports it |
| Three-finger gesture | Forward to guest Magic Trackpad |
| Four-finger tap | Reveal Henge's hidden controls |

Touch events with more than one finger use the existing emulated Magic Trackpad
USB pathway. Only one-finger direct interaction uses the virtual mouse.

Portrait mode keeps the separate **trackpad panel** for precise control.
If an external display is active, touches on the iOS device remain a trackpad,
because the remote display's absolute touch coordinates are not available.

### Implementation and caveats

macOS does not expose a native touchscreen to Henge's guest. The guest mouse
is a relative VirtIO device, and macOS applies its own pointer acceleration.
\`DirectTouchSurface\` uses the guest GPU's cursor-position feedback to
converge on a desired screen pixel location, only injecting a click near the
target. This is **experimental absolute-like pointing**, not a physical Sidecar
display or a guest touch digitizer. Large cursor jumps can take time, especially
during boot, heavy load or in high guest resolutions. The app drops a tap when
its target cannot be reached before the deadline, rather than clicking the
wrong Mac control.

The direct-touch view resets held mouse buttons and emulated fingers when
removed, cancelled, when the app goes inactive, when a sheet opens, or when
switching to Trackpad mode. The scene's background handler still releases
physical-input buttons.

The pointer controller reads back the actual guest cursor and estimates the
guest's current relative-mouse gain. Large relocations use coarse movements,
then fine corrections before a click. A fast flick-to-drag is completed after
the finger lifts if the virtual cursor needs extra time to catch up.
The guest button-down must happen even after a rapid finger lift; an earlier
state check skipped that event and dropped short window/icon drags. A bounded
watchdog releases the guest mouse button if the pointer cannot converge. Since the
guest remains a mouse, **exact Sidecar digitizer semantics are not possible**
without implementing a new, guest-supported absolute pointing device.

### Verification / hardware QA

1. Run \`swiftc -frontend -parse\` on the modified Swift sources.
2. Build on **Xcode 27** with Henge's dependencies from \`ios/README.md\`.
3. On an iPhone and iPad, test tap, double-tap, window drag, desktop icon drag,
   long-hold drag, text selection, scrolling, browser pinch, secondary click,
   four-finger reveal and switching modes mid-gesture.
4. Try landscape/portrait and zoomed view with different guest aspect ratios.
5. Test external display attach/detach and VM shutdown during a held touch.
6. Test with a hardware mouse connected and with VoiceOver/accessibility enabled.

Source parsing alone does **not** establish that the feature runs properly
on real devices or that Apple/macOS recognizes every touchpad gesture.
