# Apple Account and App Store setup

Use **Settings → Apple Account & App Store → Prepare macOS Sequoia 15.6.1**.
This selects the recommended restore and account compatibility in Install;
it does not start a download or delete a Mac. Review memory/storage and choose
Install. After setup, sign in manually in macOS System Settings and App Store.

## Try an already installed Ventura Mac

Open **Settings → Apple Account & App Store**, choose your installed Mac, then
**Enable compatibility on this Mac**. The same control is in that Mac's settings. Shut down macOS from its Apple menu first.
If Instant Resume has a saved memory session, start that session and shut down
normally; enabling will not delete it. Installation, import/export and any running
or paused VM block the change. Then start the same Mac from cold, check Details
for **Compatibility active** and attempt normal sign-in inside macOS. For Ventura,
the only measured kernel profile is **13.6, build 22G120**. Other Ventura builds
keep the original kernel behavior; they have not been verified.

This is an **unverified retrofit experiment**, not evidence that MID or Apple
Account login is repaired. It applies the same boot profile to the existing guest
without reinstalling. No guest account caches, Keychain, activation records,
NVRAM, ECID/seed, restore ROM or disk contents are edited by the setting. macOS
can itself update its state when it next boots with a different hardware profile.
A real Mac's serial is neither requested nor copied.

The profile and enable state are committed in one atomic `account-profile.json`
sidecar bound to this Mac's UUID, ECID and seed. It is read after the machines list
and before boot; a stale list cannot revert a completed change. A damaged or
foreign sidecar fails closed, without generating another identity. Disabling
restores the previous boot identifiers and retains the synthetic profile so a
later enable uses exactly the same one. It does **not** undo guest-side account,
cloud or filesystem changes. Export through Henge includes the retained profile
and enabled/disabled state in `machine.json`; import preserves both. The sidecar
is not needed in an exported folder. Ordinary Mac setting edits also reconcile
the sidecar so an older settings view cannot silently overwrite it.

The same guide is available in each Mac's settings, running-session Details and
Network & Devices. Per-Mac status distinguishes absent profile, saved profile,
waiting, board setup failure and matched compatibility. **Compatibility active
never means signed in.** Unknown native status cannot report success. A running
Mac must be shut down before preparing another installation. RAM snapshots remain
disabled while compatibility is enabled; in-process pause/continue still works.

## Ported code and scope

Adapted from liukaixiang817/Henge, GPL-2.0-or-later, pinned at
[7fbc8651e8bc01319b3fb90ac614723416d526ba](https://github.com/liukaixiang817/Henge/commit/7fbc8651e8bc01319b3fb90ac614723416d526ba).
The later source branch head 4d1c19f changes packaging names only. Imported here:
exact Darwin kernel version/delta/process-layout profiles for builds 24G90,
25G83 and 26B123. The existing synthetic identity generator, boot configuration,
scoped process allowlist and early device-tree setup were already present.
Also ported the source fork's prerequisite memory fix from
[3ff3bea](https://github.com/liukaixiang817/Henge/commit/3ff3bea1a76a1e70c1e6e989feeafdd700de348c):
release unclaimed Mac-app address reservations before VM RAM sizing, boot/resume
and installation. Claimed Mac-app rooms and live JIT mappings remain owned by
their existing users. Its real-Mach regression fixture covers allocation before
and after release, claimed ownership, release failure/retry and Swift RAM sizing.
Camera, microphone, guest disks, user accounts and private test identities from
the source branch are not imported.

The largest process layout is now accounted for in the native buffer, while
reads cover only the current profile's required span. Unknown instruction
shapes, complete Darwin strings, sysctl keys and process layouts keep the
original result. The public `sysctl` command and unrelated processes remain
outside the account-process allowlist. The earlier verified Ventura profile
remains unchanged.

## Independent kernel checks

Actual kernelcache.release.vma2 files were range-extracted from the Apple CDN
restore URLs already in Installer.swift and decompressed with ipsw 3.1.749.
`tools/audit_ventura_kernel.py` then checked each against the compiled production
matcher, native profile table, unique handler, resolved vmm-present key,
_proc_name accessor and adjacent full-name offset. The auditor name is retained
for existing tooling; it now accepts all profiles in the native table.
Full results are in [apple-account-kernel-audit.json](apple-account-kernel-audit.json).

| Restore build | Process layout | Decompressed kernel SHA-256 |
| --- | --- | --- |
| 24G90 | 0x5cc | 333e6c7e8a8082f9a2cc6ce021a5664e6cdc2b5eac2f34b822886c844a6b91f8 |
| 25G83 | 0x5cc | 268f431e7366409dc798cd8f719a93cf3a30c6f828201d8eeceae889358099c6 |
| 26B123 | 0x5bc | 01332067965f721b7e6984348510b717ff346d253d7639212dcd9f6c6161afaf |

Local portable tests: 240 process-policy/handler checks and 393 device-tree
checks pass; the process-policy suite also passes ASan/UBSan. CI must compile
the complete iOS 17 app, test setup policy/status, identity persistence,
JIT/register behavior, device/VM lifecycles and package the IPA/TIPA.

## Runtime evidence boundary

The [source fork's report](https://github.com/liukaixiang817/Henge/blob/7fbc8651e8bc01319b3fb90ac614723416d526ba/docs/apple-account-compatibility.md)
records account/MFA, App Store download and multiple iCloud-service tests on its
native macOS-hosted Henge guests. Its accompanying newer-system report covers
Tahoe and macOS 27. We have not reproduced those account tests on this fork or
on a physical iPad. Source claims, kernel audits and green builds are separate
from authentication and service delivery. FaceTime is not verified by the source;
iMessage results depend on its tested identity/account configuration.

For acceptance on the user's iPad: enable the existing-Mac experiment or create the recommended compatible Mac,
verify Details says Compatibility active, complete official password/MFA sign-in,
then download and open an authorized free App Store app. Check an iCloud Drive
file from another owned device separately. Do not infer success from a sidebar,
a catalog or a returned signing blob. If rejected, use the packaged diagnostic
command in Details → Network & Devices; its report now includes the exact macOS
build. No account password, MFA code or raw authentication headers are collected.

Apple's supported VM iCloud provisioning path and its Apple Media Services
limitations remain distinct from this experimental implementation; see
[Apple services](apple-services.md). This code makes no entitlement or supported
platform claim and does not promise every part of the ecosystem works.
