import SwiftUI

struct AppleAccountSetupView: View {
    var macID: UUID? = nil
    var identityPresent: Bool? = nil
    var nativeStatus: Int32? = nil
    @ObservedObject private var installer = Installer.shared
    @ObservedObject private var machines = Machines.shared
    @State private var canStart = false
    @State private var profileError: String?

    private var currentMac: VirtualMac? { machines.all.first { $0.id == macID } }
    private var profilePresent: Bool? { currentMac.map { $0.activeSoftwareIdentity != nil } ?? identityPresent }
    private var savedSession: Bool { currentMac.map { ExistingAccountProfile.hasSavedSession(in: $0.directory) } ?? false }

    var body: some View {
        Form {
            if let identityPresent = profilePresent {
                Section("This Mac") {
                    LabeledContent("Account compatibility", value: AppleAccountSupport.status(identityPresent: identityPresent, nativeStatus: nativeStatus))
                    Text(identityPresent
                         ? "Sign in through System Settings in macOS, then open App Store and sign in there too. An active compatibility profile does not confirm that Apple accepted the sign-in."
                         : "You can try account compatibility on this installed Mac without reinstalling macOS. Updating Henge alone does not enable the experiment.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let mac = currentMac {
                Section("Use this installed Mac") {
                    Button(mac.activeSoftwareIdentity == nil ? "Enable compatibility on this Mac" : "Disable compatibility on this Mac") {
                        do {
                            try machines.setAccountCompatibility(for: mac.id, enabled: mac.activeSoftwareIdentity == nil)
                        } catch { profileError = error.localizedDescription }
                    }
                    .disabled(!canStart || installer.busy || machines.importing != nil || machines.exporting != nil || savedSession)
                    Text("Changes apply at the next cold boot. Your installed system, apps and files stay on the same disk. The profile is saved once and reused; disabling it restores the previous virtual hardware identifiers, but does not undo changes macOS or cloud services made while it was enabled.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if savedSession {
                        Text("Start this Mac and choose Shut Down from the Apple menu first. Its saved memory session will not be deleted to enable this feature.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if !canStart {
                        Text("Shut down the running Mac before changing its account profile.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("For Ventura, the measured profile is for 13.6, build 22G120. Open About This Mac inside macOS to check your version. Other Ventura builds are not verified. A profile match does not confirm that Apple accepts account sign-in or fixes MID.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("After enabling, start this Mac, check Details for Compatibility active, then try signing in through macOS System Settings and App Store. If it fails, shut down and disable compatibility here. You do not need to install another macOS to try this path.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Set up another Mac") {
                Button("Prepare macOS Sequoia 15.6.1") { AppleAccountSupport.requestSetup() }
                    .disabled(!canStart || installer.busy)
                Text("Opens Install with the recommended system and Apple Account compatibility selected. Review the space and memory settings, then start the installation. Your current Mac stays in the Macs list.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !canStart {
                    Text("Shut down the running Mac before preparing another installation.")
                        .foregroundStyle(.secondary)
                }
                Text("This creates a separate Mac with its profile selected before installation. Existing Macs can use the experiment above. Replacing only a serial number is not a confirmed MID repair.")
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
        .alert("Account profile could not be changed", isPresented: Binding(get: { profileError != nil }, set: { if !$0 { profileError = nil } })) {
            Button("OK", role: .cancel) { profileError = nil }
        } message: { Text(profileError ?? "") }
        .task {
            while !Task.isCancelled {
                canStart = henge_vm_can_start() != 0
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
