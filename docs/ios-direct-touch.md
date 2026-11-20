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

Open **Settings → Touch Controls**, or **Details → Touch Controls** during a session.
The current USB absolute-input implementation, gestures, Pencil behavior and
upgrade instructions are documented in [Direct Touch and Pencil](direct-touch-pencil.md).
The earlier GPU cursor-feedback positioning loop is no longer used.
