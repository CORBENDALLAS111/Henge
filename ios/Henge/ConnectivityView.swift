import SwiftUI

/// One destination shared by app Settings and the running Mac's Details.
struct ConnectivityView: View {
    var typeDiagnostics: (() -> Void)? = nil
    static let discoveryKey = "henge.network.localDiscovery"
    @AppStorage(Self.discoveryKey) private var discovery = false
    @State private var network = LocalNetworkStatus()
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                LabeledContent("iPad connection", value: network.connection)
                LabeledContent("Mac connection", value: "Shared network (NAT)")
                Toggle("Discover local devices", isOn: $discovery)
                Text("Find iPhones, shared folders, SSH and screen sharing on the same network. Allow Local Network access when iPadOS asks. Devices must also allow connections from this iPad.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Open iPadOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } header: { Text("Local network") } footer: {
                Text("macOS uses a virtual Ethernet connection through this device. Change Wi-Fi networks in iPadOS Settings. Incoming connections to the Mac and a separate Wi-Fi adapter are not provided.")
            }
            Section("Sideloadly over Wi-Fi") {
                Text("Connect the other iPhone or iPad to the same network. It must already trust the computer and have Wi-Fi sync enabled before wireless sideloading can work.")
                Text("Discovery does not create a trusted pairing. USB pairing passthrough and wireless installation from this virtual Mac have not been verified.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("Sideloadly setup instructions", destination: URL(string: "https://sideloadly.io/faq.html")!)
            }
            Section("Bluetooth accessories") {
                Text("Pair your keyboard, mouse, controller and headphones in iPadOS Settings. Henge forwards supported input and audio to the Mac.")
                Text("macOS cannot pair directly with the iPad's Bluetooth radio. Arbitrary Bluetooth devices are not forwarded.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Apple Account") {
                Text("Sign in inside macOS System Settings. Henge never asks for your password or verification code.")
                Text("The Ventura compatibility option is experimental and is chosen when creating a new Mac. A matching compatibility profile does not confirm that Apple accepted the sign-in. An “MID is invalid” error needs guest diagnostics; changing a serial number alone is not a verified fix.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let typeDiagnostics {
                    Button("Type Diagnostic Command", action: typeDiagnostics)
                    Text("Open Terminal in the Mac first. This types the command; press Return to run it. It reports the system version, time, DNS and TLS checks without reading account credentials.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ShareLink("Share Diagnostic Command", item: Sharing.diagnosticsCommand)
                Link("Apple's virtual machine account requirements", destination: URL(string: "https://developer.apple.com/documentation/virtualization/using-icloud-with-macos-virtual-machines")!)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Desk.page)
        .navigationTitle("Network & Devices")
        .navigationBarTitleDisplayMode(.inline)
        .task { network.start() }
        .onDisappear { network.stop() }
        .onChange(of: discovery, initial: true) { _, enabled in henge_vm_set_local_discovery(enabled ? 1 : 0) }
    }
}
