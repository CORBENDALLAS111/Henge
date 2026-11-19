# Ventura Apple Account experiment

**Sign-in, two-factor authentication and App Store downloads are unverified.**
This is an experimental port, not an Apple-supported VM identity implementation.
It does not create an Apple Account. No credentials, tokens, private hardware
identities, guest disks or Apple binaries are included.

The user's App Store screenshot says “MID is invalid”; it does not establish
which identity/provisioning check failed. The catalog loaded, but authenticated
services did not. Replacing the default serial `1234` alone is not a demonstrated
fix. Guest DNS/TLS/clock checks remain in `tools/check-apple-services.sh`.

## Source and exact target

Adapted identity/profile, scoped kernel compatibility and tests from
[liukaixiang817/Henge commit 7fbc8651e8bc01319b3fb90ac614723416d526ba](https://github.com/liukaixiang817/Henge/commit/7fbc8651e8bc01319b3fb90ac614723416d526ba),
GPL-2.0-or-later. Its author reports services working on other macOS versions in
[upstream issue 119](https://github.com/Leviidev/Henge/issues/119#issuecomment-6845000560).
Those claims are not runtime evidence for this port. Its camera/microphone,
JIT reservation and packaging changes are not imported.

Only **Ventura 13.6, build 22G120** is enabled. The measured Apple vma2 kernel:

- SHA-256 of decompressed Mach-O: `f4d157671bb7e06d4e4d0ad6b6ecfdc6b747ccafb8927a35c1f72b4cd5e20bc2`.
- Darwin `22.6.0`, XNU `8796.141.3.700.8~1/RELEASE_ARM64_VMAPPLE`.
- One complete 104-byte handler shape resolves to `vmm-present`.
- Handler minus Darwin-version-string virtual address: `0x10a69cf`.
- `_proc_name` uses `proc + 0x5b8`; `_proc_best_name` confirms the adjacent full
  name at `0x5c9`. Newer macOS offsets are deliberately rejected.
- XNU's matching `bsd/sys/sysctl.h` confirms `sysctl_req.p` is its first field.

These were measured from the public restore URL already used by the installer.
Reproduce without running the Apple binary:

```sh
ipsw extract --remote --pattern 'kernelcache.*vma2' --output /tmp/ventura-kernel \
  'https://updates.cdn-apple.com/2023FallFCS/fullrestores/042-55833/C0830847-A2F8-458F-B680-967991820931/UniversalMac_13.6_22G120_Restore.ipsw'
ipsw kernel dec /tmp/ventura-kernel/22G120__MacOS/kernelcache.release.vma2 --output /tmp/ventura-dec
python3 tools/audit_ventura_kernel.py /tmp/ventura-dec/kernelcache.release.vma2.decompressed
```

## Behavior and boundaries

Install macOS → Ventura 13.6 → **Apple Account compatibility (experimental)**.
The switch defaults off and is available only while creating a new VM. Existing
VMs, their ECID/seed, disk, auxiliary storage, account state and settings are not
migrated or regenerated. Keep the previous Ventura VM until testing succeeds.
A new profile stays with its VM on export/import; importing an already-listed
profile is refused. Ordinary VMs clear all profile environment fields at boot.

The new VM generates a persistent synthetic serial, checksum-valid board serial
and distinct network addresses. At early kernel boot, a bounded parser supplies
root board/model fields, retaining virtual driver-compatible strings. The JIT
substitutes the handler's result only after matching the full instruction shape,
exact NUL-terminated Darwin version and resolved sysctl key. It requires successful
board-field setup. A fixed allowlist of account/cloud processes sees VMM=0;
unknown callers, `sysctl`, WindowServer, software update and kernel callers retain
the original result. Guest files, TLS trust and authentication replies are not
patched. An unsupported kernel retains its original sysctl behavior.

This hides virtualization from those services; it does not provide Apple's
Secure Enclave-derived VM identity. Apple's documented iCloud support requires
a new macOS 15+ VM on a macOS 15+ Apple silicon Mac using Virtualization.framework.
Apple separately excludes Media Services from supported VMs. See
[Apple services](apple-services.md) for those platform limitations.

RAM save/restore is refused for experimental VMs; in-process pause/continue is
retained. After Henge terminates, use a cold boot. Regular VMs retain their
existing Instant Resume behavior. Host identity cosmetics are skipped only for
experimental VMs so they cannot race the synthetic board/model setup. Custom
Resolution, external displays and all input paths remain unchanged.

Logs contain bounded allowlisted process names, match/setup state and fixed
build names. They do not print identifiers, account names, credentials or tokens.
The information panel says whether compatibility matched, never “signed in”.

## Verification and acceptance

Local portable policy/device-tree tests, including ASan/UBSan, pass. The actual
Ventura kernel passes the offline audit. CI must additionally pass Swift parsing,
full iOS SDK/native compilation, identity persistence, JIT/register preservation,
VM lifecycle including ordinary→experimental→ordinary transitions, and the full
IPA/TIPA build. Neither audit nor build verifies authentication.

On an owned iPad, create the separate Ventura test VM and boot normally. Confirm
the information panel says compatibility matched, then sign in manually through
macOS System Settings. Passwords and MFA codes stay on the device. Record only
the visible error if rejected. Separately verify an authorized free App Store
app actually downloads and opens; a signed-in sidebar is insufficient. Check a
clean shutdown/cold boot, identity persistence, input, scrolling/resizing and
external-display routing. These on-device steps have not been performed here.
