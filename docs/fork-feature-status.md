# Fork features and acceptance

This inventory describes the inherited feature branches plus this input/network
repair. “Implemented” does not mean a feature has been verified on an iPad.
The main branch alone does not contain all of these features; this branch builds
on `feat/pencil-file-bridge` (`808b71d`).

| Feature | Place in the interface | Implementation / acceptance |
| --- | --- | --- |
| Custom guest resolution | Each Mac → Screen → Resolution | Saved per Mac; validated dimensions/pixel budget; next boot |
| Direct Touch | Settings or Details → Touch Controls | USB absolute pen, jitter-tolerant tap/drag classification, one-finger context hold |
| Apple Pencil / Pencil Pro | Same Touch Controls → Gestures & Apple Pencil | Tip click/drag, hover, pressure/tilt/roll, hold-to-double-click; real Pencil QA required |
| Touch cursor feedback | Direct Touch surface | Contact circle while touching; composited arrow hidden for fingers, restored for Pencil/mouse |
| Mouse/keyboard/controllers/audio | Details → Connected devices | Existing iPadOS forwarding; generic USB controller; no arbitrary Bluetooth radio passthrough |
| File import/export and drag/drop | Session Shared Files | Existing shared-folder provider path; cancellation/collision rules tested; guest drag/drop depends on helper |
| Local network discovery | Settings or Details → Network & Devices | Opt-in system Bonjour relay for iPhone, SMB, SSH and screen sharing; real LAN QA required |
| Apple Account compatibility | Settings → Apple Account & App Store; compatible new Mac installation | Ventura plus pinned Sequoia/Tahoe/macOS 27 profiles; account sign-in on this fork remains unverified |
| Apple transport diagnostics | Details → Network & Devices → Type Diagnostic Command | Packaged guest script; types without pressing Return; no account databases or tokens collected |
| External display | Existing session display routing | Direct Touch stays local to displayed image; external mode retains trackpad controls |
| GPU fixes/diagnostics | Existing display controls and bounded logs | Inherited surface validation/format fixes; tested by renderer fixtures; visual guest acceptance still required |

The two settings destinations reuse the same touch control rows and gesture
guide. Network & Devices is also one shared view, with native navigation/Form
layout, Dynamic Type, text labels and no new theme or third-party UI dependency.
Live settings act immediately; guest device descriptor changes require a clean
shutdown and cold boot. Existing Mac data and identities are not regenerated.

## Device acceptance

1. Cleanly shut down the Mac, install the updated build, then cold boot.
2. Finger: Dock tap without drag, two taps to open a file, window drag, text
   selection, stationary context hold, two-finger scroll and mode change mid-drag.
3. Pencil: hover without clicking; tap; two taps; hold still then lift; hold then
   move; pressure/tilt/roll in an app that consumes them; squeeze per preferences.
4. Connect/disconnect a physical mouse; attach/detach a monitor; rotate/zoom the
   display while touching; background/reopen while dragging. No button may stick.
5. Enable discovery, grant Local Network access, then browse a known SMB/SSH
   service in the guest. Check the discovered IPv4 endpoint is reachable. Disable
   discovery and verify new discovery answers stop without breaking Internet DNS.
6. Test a trusted, Wi-Fi-sync-enabled second iPhone separately. Seeing its
   Bonjour service does not establish trusted pairing or a successful install.
7. Run guest Apple diagnostics and record the visible account error plus macOS
   version and compatibility-match status. Apple sign-in is a separate runtime
   result, not inferred from generated identifiers or a green build.
