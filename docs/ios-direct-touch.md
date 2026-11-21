# Henge iOS — Custom resolution and Direct Touch

This fork adds two independently selectable features:

## Guest resolution
Open **Macs → [Mac] → Screen → Resolution**. Select **2560 × 1440 (QHD / 2K)**
for that exact guest pixel size, or **Custom** for another size. Valid custom
values save automatically while editing and on leaving the screen. Invalid
partial drafts retain the last valid configuration; no separate Apply step is
required. Finish by shutting down macOS from its Apple menu and starting it
again; an already running or paused desktop retains its boot-time display.

- Valid width: 640–7680 px; height: 480–4320 px; budget: 8,294,400 pixels.
- Explicit custom dimensions take priority over a stale saved Retina flag.
- Non-Retina modes retain the original 1080p pixel density at higher sizes;
  Retina retains its explicit physical-panel dimensions. macOS's ‘Looks like’
  size can differ from physical pixel dimensions in Retina mode.
- Selected dimensions are saved per Mac and included in Henge export/import.
  Old manifests without display keys remain readable.
- Starting from Home resolves the latest saved Mac, and recording last-used
  time updates only that field rather than writing an old settings snapshot.
- **Session Details → Display** shows selected pixels and actual guest scanout
  pixels. Scanout uses a locked metadata read, with no full-frame CPU readback.
  Before the guest draws it says ‘Waiting for the desktop’ instead of treating
  the requested size as proof of the actual output.
- Existing Retina, Performance, Fit and Full HD choices remain available.

The native VM lifecycle fixture alternates 1080p/QHD sessions, calls the same
app bridge, and inspects the actual shared mode page through the production PVG
command path. It checks dimensions, stable non-Retina density, invalid-mode
rejection, explicit Retina size and the not-yet-drawn readback state. Swift tests
cover preset/custom validation, saved-size roundtrip and Retina precedence. These
checks do not substitute for reading the user's real macOS display after reboot.

## Touch control

Open **Settings → Touch Controls**, or **Details → Touch Controls** during a session.
The current USB absolute-input implementation, gestures, Pencil behavior and
upgrade instructions are documented in [Direct Touch and Pencil](direct-touch-pencil.md).
The earlier GPU cursor-feedback positioning loop is no longer used.
