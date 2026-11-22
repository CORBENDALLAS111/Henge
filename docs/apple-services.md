# Apple services in Henge

Apple Account and Mac App Store login have **not been reproduced in this fork**.
This build extends the opt-in compatibility path to the exact Sequoia 15.6.1,
Tahoe 26.6.2 and macOS 27.2 restore builds, retaining the earlier Ventura 13.6
experiment. See [setup and verification](apple-account-setup.md).

The source fork reports successful account/App Store and cloud-service tests on
its native macOS-hosted emulator. Those are useful upstream results, not proof
of this iOS build or the user's existing VM. The three added kernel profiles
were independently audited against Apple's actual restore kernels. No account
credentials, physical machine identifiers or provisioned guest images are included.

The earlier user screenshot reported **"MID is invalid"** in Ventura App Store.
No guest account-service log or affected live VM was provided. Its underlying
error domain/code remains unknown. Account details are deliberately omitted.

## Observed machine-identity rejection

"MID is invalid" is an identity-related sign-in rejection, rather than a report
of a bad password, missing DNS answer or failed certificate. It does not reveal
which internal identifier/provisioning check Apple rejected. Henge currently has
no supported way to provision an Apple-authenticated machine identity for this
Ventura guest. The experiment generates an independent software identity and changes selected
account services' view of the virtual-machine flag in a measured guest kernel.
Whether that resolves this Ventura rejection is untested; no successful Apple
Account or App Store sign-in is claimed. Network repairs
can address a separately demonstrated transport fault; they cannot supply the
missing service authorization. Preserve the VM's existing auxiliary storage and
Keychain rather than regenerating identifiers or deleting account state.

## What the code establishes

- `host/net_slirp.c` provides IPv4 NAT, DHCP and a guest DNS address. The system
  resolver proxy in `host/dns_proxy.c` handles UDP DNS; unsupported queries and
  TCP DNS go through libslirp. IPv6 networking is not enabled in this NAT.
- Guest HTTPS uses the guest's own TLS implementation, trust store and clock.
  The restore downloader's `host/curl_shim.m` does not implement guest HTTPS.
  No certificate checks are disabled by this change.
- `devices/pl031.c` reads host wall time plus the guest-set offset. A wrong host
  date or guest offset can still break TLS. A build runner's connectivity says
  nothing about a particular guest's connectivity.
- The disk and auxiliary storage persist across boots. Account and Keychain
  services run inside macOS; the host cannot infer whether their databases are
  healthy or whether a daemon is merely waiting to be launched on demand.
- `devices/cfg.c` supplies an emulated VM identity, with default serial `1234`.
  Ordinary Macs keep that default; opted-in new Macs pass a persistent synthetic
  serial, board identity and distinct network addresses through the native bridge.
  Persisted ECID/seed and cosmetic model changes are not Apple's VM identity provisioning.
  Changing these values or copying a physical Mac's serial is not a login fix.

## Platform limitation

Apple's [VM iCloud documentation](https://developer.apple.com/documentation/virtualization/using-icloud-with-macos-virtual-machines)
describes a macOS 15+ Virtualization.framework host creating a new macOS 15+ VM
with a restore-image hardware model and a VM identity derived from the host's
Secure Enclave. Upgrading an older VM does not provide that support. Henge's
vmapple device emulation on iOS does not implement that provisioning path.

A legitimate supported iCloud architecture would run the VM on an Apple silicon
Mac using Virtualization.framework, preserving its machine identifier and
auxiliary storage, with the iOS app acting as a remote display/input client.
Local emulation would need an Apple-supported equivalent identity/provisioning
capability on iOS; no such integration exists in this project. Adding an arbitrary
Secure Enclave emulation, model string or entitlement cannot establish it.

Apple separately lists [Apple Media Services, including apps, as unavailable in
these VMs](https://support.apple.com/en-us/120468). Therefore even a supported
iCloud VM backend would not establish Mac App Store support. Apple would need
to provide support for that service; use a supported physical Mac for it today.

## Diagnose a particular VM

Run `bash tools/check-apple-services.sh` **inside the guest**, copying the script
there first. It reports only OS/architecture, clock, route availability, DNS
success, curl exit/status/certificate result, HTTPS Date clock difference and
daemon presence. It sends unauthenticated requests to three fixed public Apple
endpoints. It does not read Keychains, account databases, identifiers, tokens,
cookies or HTTP bodies and never attempts sign-in. A 3xx/4xx HTTP response can
still establish successful DNS/TCP/TLS; `curl_exit=0` does not establish login.

For an existing Ventura guest, repeat the failed login and then run
`bash check-apple-services.sh --account-errors` within ten minutes. The script
also checks the exact kernel build, whether the legacy model is visible and
whether the serial is still the `1234` placeholder. It outputs only yes/no or
fixed status values for these identity indicators. A recognized build or a
non-placeholder serial alone does not mean compatibility or sign-in succeeded.

The optional error mode reads recent error/fault events from selected account
processes, and outputs only allowlisted error-domain names, integer codes and
counts. Raw messages, account names, tokens and identifiers are never printed
or written to a file. The log reader's exit code is reported: no detected pairs
can mean unavailable/redacted logs, not absence of an authentication failure.
Nested errors or unrelated account events can appear in the same ten-minute
window; correlate them with the attempted login rather than assuming a cause.

The current script can be used without updating the IPA. Run inside Ventura:

```sh
curl -fsS 'https://raw.githubusercontent.com/CORBENDALLAS111/Henge/fix/apple-account-compatibility/tools/check-apple-services.sh' | /bin/bash -s -- --account-errors
```

This is a read-only diagnostic, not an account reset. Do not rotate the saved
identity or erase caches/Keychains merely because App Store still says Sign In.
The user's earlier report had reached MFA before an app-version incompatibility;
that observation does not confirm completion of the current login attempt.

- Missing route/DNS: check Henge's NAT startup and bounded DNS failure messages
  in `henge.log`, and compare a different network/VPN configuration.
- Curl 6/7/28: resolution, connection or timeout failure respectively. Curl 35
  indicates TLS negotiation; 60 indicates certificate validation. Check the
  guest date and normal macOS certificate updates rather than disabling trust.
- Large guest/HTTPS Date difference: correct device and guest Date & Time.
- Transport succeeds but sign-in is rejected: record the exact user-visible
  error code and macOS version locally. Inspect `akd`, `accountsd`,
  `storeaccountd`, `appstoreagent`, `trustd` and `securityd` in guest Console.
  Do not export full account logs, tokens, account names or Keychain contents.
  A stopped on-demand daemon alone is not a diagnosis. Do not reset Keychains
  or remove account data without first establishing a specific guest-side fault.

The new host messages omit DNS query names and payloads and cap resolver failure
details at 12 per session. They diagnose transport failures, not authentication.
