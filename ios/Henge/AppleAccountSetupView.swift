import SwiftUI

struct AppleAccountSetupView: View {
    var identityPresent: Bool? = nil
    var nativeStatus: Int32? = nil
    @ObservedObject private var installer = Installer.shared
    @State private var canStart = false

    var body: some View {
        Form {
            if let identityPresent {
                Section("This Mac") {
                    LabeledContent("Account compatibility", value: AppleAccountSupport.status(identityPresent: identityPresent, nativeStatus: nativeStatus))
                    Text(identityPresent
                         ? "Sign in through System Settings in macOS, then open App Store and sign in there too. An active compatibility profile does not confirm that Apple accepted the sign-in."
                         : "This Mac was created without the account compatibility profile. Updating Henge does not add it to an existing installation.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Set up Apple Account") {
                Button("Prepare macOS Sequoia 15.6.1") { AppleAccountSupport.requestSetup() }
                    .disabled(!canStart || installer.busy)
                Text("Opens Install with the recommended system and Apple Account compatibility selected. Review the space and memory settings, then start the installation. Your current Mac stays in the Macs list.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !canStart {
                    Text("Shut down the running Mac before preparing another installation.")
                        .foregroundStyle(.secondary)
                }
                Text("The profile is created before macOS is installed and stays with that Mac. An existing Mac needs a new installation for this setup. Replacing only a serial number is not a confirmed MID repair.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Supported systems") {
                Text("Sequoia 15.6.1 is recommended. Compatibility also recognizes Tahoe 26.6.2 and macOS 27.2. The earlier Ventura 13.6 experiment remains available.")
                Text("The source fork reports account sign-in, App Store downloads and several iCloud services on the newer systems. These results have not yet been reproduced on your iPad. FaceTime and every part of the ecosystem are not guaranteed.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("Read the source fork's test results", destination: URL(string: "https://github.com/liukaixiang817/Henge/blob/7fbc8651e8bc01319b3fb90ac614723416d526ba/docs/apple-account-compatibility.md")!)
            }
            Section("If sign-in fails") {
                Text("Open Details → Network & Devices in the running session and use Type Diagnostic Command with Terminal open. The report includes the macOS version and build, time and connection checks. Keep your password and verification code inside macOS.")
                Text("A matched compatibility profile, a visible App Store catalog or a successful build does not establish sign-in or cloud synchronization.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Desk.page)
        .navigationTitle("Apple Account & App Store")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                canStart = henge_vm_can_start() != 0
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
