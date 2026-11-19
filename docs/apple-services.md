# Apple services in Henge

Apple Account and Mac App Store login have **not** been verified. The existing
README reports a verification error. No guest account-service logs, affected VM
or signed-in device were available for this investigation, so its exact error
domain/code and any concurrent network failure remain unknown.

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
  The iOS bridge does not supply a serial override. Persisted ECID/seed and
  cosmetic About This Mac model changes are not Apple's VM identity provisioning.
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
