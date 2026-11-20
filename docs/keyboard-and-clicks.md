# Stationary clicks and keyboard viewport

This follows the user's failed on-device tap test after the earlier gesture fix.
The classifier alone was insufficient: down/up/leave could still reach the guest
within three 1-ms USB samples. We now hold each button state and post-release
proximity for at least 50 ms. Hover/drag motion keeps 1-ms service. Cancellation
bypasses the hold and releases immediately. Clock rollback, endpoint reset and
queue overflow retain their existing cancellation behavior.

The production-controller fixture queues two clicks at exactly the same XY and
samples delivered state every 16 ms. Both down/up pairs must remain observable.
The previous 1-ms-only transport loses those transitions before the first
sample. This is a transport regression test, not proof that it models every
WindowServer consumer. Real Dock/control tapping still requires the user's iPad.

## Settings

Settings and running-session Details contain the same Keyboard section:

- Manually: retain the keyboard button.
- On direct taps: open after a classified finger/Pencil click; never on movement
  or a drag. This mode needs no guest helper.
- On text fields: open only after a fresh editable-focus report following that
  tap. Install/update the guest helper using Details → Sharing → Type the Set Up
  Command, then grant henge-agent Accessibility permission inside macOS.
- Keep Mac screen size: enabled by default. The image keeps its scale and
  horizontal position, translates upward to expose the tapped point, and adds a
  Move Mac view handle above the keyboard for bounded vertical panning.
  Panning changes the viewport without sending a guest drag or hiding the keyboard.

Auto-opening waits until the pen queue has delivered the complete click. Opening
earlier could resize/remap the input surface and cancel the click itself.
Keyboard frames are converted through the actual window for split views and
Stage Manager. Keyboard safe-area resizing is suppressed at the session root.
The old fitting layout remains selectable by disabling Keep Mac screen size.

## Focus privacy and lifecycle

Only text-field roles and normalized element geometry are sampled through the
guest Accessibility API. No field value, selected text, label, password or
keystroke is read. The opt-in flag is served only on the existing guest-local
10.0.2.4 helper channel. Turning off field detection clears cached metadata.
Malformed/nonfinite/out-of-range reports are rejected. Reports expire after two
seconds, and a keyboard request requires a report received after the tap.
The helper prompts for Accessibility once per enabled session. Unsupported
custom controls or missing permissions retain the manual keyboard button and
the direct-tap mode as alternatives.

Tests cover parser rejection, opt-in HTTP endpoints, permission state and mode
reset; viewport tests cover scale preservation, field visibility, vertical
bounds and invalid geometry. Full SDK/native compilation and IPA helper-content
verification run in CI. On-device keyboard behavior, apps' AX role support and
the original tapping symptom remain runtime acceptance checks.

Reference: [Microsoft Remote Desktop iOS navigation](https://learn.microsoft.com/en-us/previous-versions/remote-desktop-client/remote-desktop-ios-ipados)
documents displaying a pan control with the keyboard. This implementation uses
that interaction pattern without claiming Windows' protocol-specific integration.
