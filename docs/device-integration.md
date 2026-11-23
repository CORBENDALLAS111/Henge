# Host device status and controls

The guest helper adds a working status-bar menu inside macOS. It reads live host
information through Henge's existing private guest sharing transport. This is a
host integration menu, **not an emulated battery/SMC driver**. macOS System
Settings, IOKit power-source APIs and its own battery indicator still see the
existing virtual desktop hardware.

## Setup

1. Install an IPA that includes this feature. The verified V1 smart-touch IPA
   (`78fcd4cceb03`) predates device integration.
2. In the session's Details → Sharing, use **Type the Update Command** in the
   guest Terminal to install/update `henge-agent`. Existing helpers do not
   automatically acquire new code when the IPA is replaced.
3. Details → **Device Integration** shares status by default. Turn on **Allow
   guest brightness and Mac audio controls** to enable the guest sliders and
   mute action. This permission is off by default and stored per VM.
4. Open the iPhone/iPad charge menu in the macOS menu bar. No Accessibility
   permission is needed for device status/controls. Smart touch still needs its
   separate guest Accessibility permission and host opt-in.

The menu shows:

| Reading / control | Implementation and boundary |
|---|---|
| Charge percentage | `UIDevice.batteryLevel`; unknown stays unknown, never guessed |
| Power state | Unknown, on battery, charging, or plugged in and full; this is not a charger wattage or USB data-cable detector |
| Low Power Mode / thermal state | Public `ProcessInfo` readings; no private temperature sensor access or guest CPU-frequency claim |
| Audio output | Generic active route types: speaker, receiver, headphones/line, USB, Bluetooth, AirPlay, HDMI/DisplayPort, other; no accessory names/identifiers |
| Video output | Whether Henge is currently rendering the VM on an external display or the device screen; a merely connected unused cable is not reported as an active VM output |
| Peripherals | Host `GameController` keyboard, mouse/trackpad and controller presence; no raw USB enumeration |
| Device system volume | Read-only `AVAudioSession.outputVolume` in the guest; a visible `MPVolumeView` in Henge offers the user's real system control |
| Mac audio level / mute | Actual attenuation in Henge's AudioUnit render callback, for S16, S32 and float guest PCM; affects this VM, does not programmatically set system output volume |
| Device screen brightness | Actual `UIScreen.main.brightness`, with readback; affects the physical iPhone/iPad main screen, not the guest image dimming setting or an external monitor |

The host Details panel also offers VM audio gain, physical screen brightness and
the native system-volume slider. Gain is saved per VM. Brightness remains an
OS/device setting: Apple documents that a change can persist after an app closes
until the device locks. Guest controls are accepted only while this VM's Henge
session is active in the foreground. Henge currently has one global audio/VM
context; this does not introduce simultaneous independent VM support.

The ordinary macOS Control Center volume/brightness keys are **not intercepted**
and do not automatically manipulate these new controls. No virtual USB battery,
kernel extension, private entitlement, new display descriptor, identity reset or
snapshot ABI change is introduced. Headset routing still belongs to iPadOS;
microphone return audio and external-monitor brightness remain unimplemented.

## Transport and reliability

`GET /.henge/device-status` returns version-1 bounded JSON containing only fixed
codes, numeric levels and opaque session/revision strings. No telemetry is saved
to the guest filesystem. The existing helper's clipboard and shared-folder
workers remain separate. No host TCP listening port is added.

`PUT /.henge/device-control` accepts only a strict four-token body:
`session field revision value` (field `0` = VM gain, `1` = physical brightness,
value 0…1). The in-memory mailbox coalesces each field independently, reserves a
revision on acceptance and requires a matching revision on the next write.
Duplicate/replayed requests, a previous session's helper and requests racing a
newer local adjustment cannot replace the current value. An acknowledgment
records the actual applied level, including gain quantization or OS readback.
Commands arriving during an older apply remain queued until that apply is
acknowledged.

The foreground publisher samples general status once per second, checks controls
at 10 Hz and uses a new random lease for each permission/foreground session.
Host status expires after four seconds. Resuming publication after a stall
invalidates old queued commands. Cancelling an older task cannot stop its
replacement. The guest menu disables stale controls, uses background requests
with three-second socket/connect timeouts and reports a conflict instead of
blindly retrying a write against newer state. It never treats an unavailable
host as 100% battery or a successful command.

## Source and verification

- [HostDeviceBridge.swift](../ios/Henge/HostDeviceBridge.swift): supported iOS
  readings, foreground loop, controls and native system-volume UI.
- [DeviceIntegrationSettings.swift](../ios/Henge/DeviceIntegrationSettings.swift):
  per-VM preferences and numeric validation.
- [host_device.h](../host/host_device.h), [share.c](../host/share.c): state,
  freshness, revisions and real guest HTTP endpoints.
- [device-menu.m](../tools/device-menu.m), [henge-agent.m](../tools/henge-agent.m):
  AppKit menu and background transport, built into the shipped compressed helper.
- [audio_mac.c](../host/audio_mac.c), [audio_gain.h](../host/audio_gain.h):
  atomic gain and unaligned-safe PCM attenuation; guest consumption/timing stays
  intact even when muted.

Run `make test-host-device` on macOS. It checks the state machine, PCM boundaries,
per-VM settings and the production sharing server's HTTP control exchange.
CI also compiles the full Swift app, guest helper and native engine, runs the
existing input/render/lifecycle suites, and checks both endpoint strings in the
helper actually packaged in the IPA. Portable C state/DSP tests pass locally
with AddressSanitizer and UndefinedBehaviorSanitizer; settings and gesture
fixtures pass with Swift 6.2.3 under WSL. WSL cannot compile macOS filesystem APIs
used by the real sharing server; that integration test requires the Mac runner.
Build results are recorded separately; source implementation is not hardware
acceptance.

Physical-device acceptance remains required:

1. Check unknown/unplugged/charging/full transitions, Low Power Mode and thermal
   readings against the device's own status, including after locking/backgrounding.
2. Connect/disconnect USB/Bluetooth headphones, keyboard, mouse and controller;
   confirm actual sound output and generic route status follow iPadOS.
3. Attach/detach the external VM display and verify output status and input
   mapping; audio and video routes may differ.
4. Enable guest controls, move both sliders, mute/unmute during playback and
   adjust local brightness/VM gain concurrently. Verify readback, conflicts,
   stale-state disabling and permission-off behavior.
5. Suspend/resume, shut down/restart, reopen another VM and update the helper.
   Verify no old command applies to a replacement session, and clipboard, Files,
   smart-touch behavior and guest data remain intact.

## Public API references

- [Battery monitoring](https://developer.apple.com/documentation/uikit/uidevice/isbatterymonitoringenabled),
  [battery states](https://developer.apple.com/documentation/uikit/uidevice/batterystate-swift.enum).
- [Audio route](https://developer.apple.com/documentation/avfaudio/avaudiosession/currentroute),
  [read-only outputVolume](https://developer.apple.com/documentation/avfaudio/avaudiosession/outputvolume),
  [MPVolumeView](https://developer.apple.com/documentation/mediaplayer/mpvolumeview).
- [Main-screen brightness](https://developer.apple.com/documentation/uikit/uiscreen/brightness).
