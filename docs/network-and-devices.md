# Network & Devices

The same destination is available in **Settings** and a running Mac's **Details**.
It uses Henge's existing Form/navigation styles and Dynamic Type. It distinguishes
host connectivity, guest networking, accessory forwarding and account support.

## Local network

macOS retains the existing IPv4 libslirp NAT: `10.0.2.15`, router `10.0.2.2` and
DNS `10.0.2.3`. Outbound TCP/UDP to LAN IPv4 addresses uses the iOS connection and
requires Local Network permission. Wi-Fi credentials and network selection stay
in iPadOS; the guest has virtual Ethernet, not a Wi-Fi radio.

**Discover local devices** is off by default. When enabled, guest queries for
`_apple-mobdev2._tcp`, `_smb._tcp`, `_ssh._tcp` and `_rfb._tcp` are resolved through
DNSServiceQueryRecord on iOS. These types are declared in NSBonjourServices.
The relay returns PTR/SRV/TXT/ANY service records and A/AAAA .local host lookups
as IPv4 mDNS replies on the guest network. Normal DNS has an independent failure
budget: unanswered Bonjour queries do not disable Internet DNS. The relay is
live-configurable, bounded by the existing 64-query limit, and drained with the
network session before queues are destroyed. Disabling suppresses queued replies.

The relay handles up to 16 questions per packet, bounded backwards name
compression, QU questions and known-answer sections. It does not forward raw
multicast on the physical network, enumerate arbitrary service types, advertise
guest services to the LAN, or give the guest an inbound LAN address. IPv6
link-local addresses and interface scope cannot be routed through IPv4 NAT; a
discovered device still needs a usable IPv4 address and a reachable service.

This is service discovery, not a complete Ethernet bridge. Bonjour results can
outlive a connection until their cache TTL expires. Authentication, firewall
rules, VLAN/client isolation and pairing remain the service's responsibility.

## Sideloadly

The mobile-device service can now be discovered by the guest. This does not
import or generate pairing records. Sideloadly's official instructions require
an initial trusted USB connection and Wi-Fi sync enabled in Finder. Henge has
no verified USB passthrough path to another attached iPhone/iPad. Discovery,
trusted pairing and successful wireless installation must each be tested on
real devices; this implementation does not claim installation works.

## Bluetooth and Apple Account

Keyboard/mouse/controller/audio forwarding use the existing iPadOS connections.
Core Bluetooth's accessory APIs do not expose an arbitrary HCI radio for the
guest to own. There is no fake Bluetooth or Wi-Fi toggle in macOS settings.

See [the Ventura compatibility experiment](ventura-account-experiment.md) for
what exists for Apple Account, the exact supported build, diagnostics and the
remaining MID investigation. No physical Mac's serial is copied and no account
success is inferred from a generated identity or successful build.

## Verification

`make test-mdns-proxy` uses production DNS code with a fake system resolver:
opt-in gating, declared service policy, multiple compressed questions, multicast
MAC/IP/ports/TTL, IP and UDP checksums, query teardown and Internet-DNS isolation.
`test_dns_lifecycle` additionally covers pending callbacks, cancellation and DNS
fallback/restart. Real LAN discovery and pairing still require an iPad and guest.

Sources:

- [Apple TN3179: local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [DNSServiceQueryRecord](https://developer.apple.com/documentation/dnssd/dnsservicequeryrecord(_:_:_:_:_:_:_:_:))
- [Sideloadly FAQ](https://sideloadly.io/faq.html)
- [Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
- [Apple VM iCloud requirements](https://developer.apple.com/documentation/virtualization/using-icloud-with-macos-virtual-machines)
- [SwiftUI Pro skill](https://github.com/twostraws/SwiftUI-Agent-Skill)
