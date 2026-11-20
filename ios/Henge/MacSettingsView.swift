import SwiftUI

/// One Mac: what it has, and what can be done with it.
struct MacSettingsView: View {
    @ObservedObject private var machines = Machines.shared
    @Environment(\.dismiss) private var dismiss
    @State private var mac: VirtualMac
    @State private var confirmDelete = false
    @State private var movingExport = false
    @AppStorage("henge.cpus") private var cpus = 4
    @State private var customWidth: String
    @State private var customHeight: String

    init(mac: VirtualMac) {
        _mac = State(initialValue: mac)
        _customWidth = State(initialValue: String(mac.screen.width))
        _customHeight = State(initialValue: String(mac.screen.height))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                DeskHeading("Name")
                TextField("Name", text: $mac.name)
                    .font(.system(size: 16))
                    .submitLabel(.done)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 14)
                    .deskCard()
                    .onSubmit(save)

                DeskHeading("Memory")
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(mac.ramMB / 1024) GB").font(.system(size: 26, weight: .bold))
                        Spacer()
                        Text(Entitlements.increasedMemory ? "Outside the app's limit once JIT is on" : "Used from free storage if needed")
                            .font(.system(size: 13)).foregroundStyle(Desk.dim).multilineTextAlignment(.trailing)
                    }
                    Stepper("Memory", value: Binding(get: { mac.ramMB / 1024 }, set: { mac.ramMB = $0 * 1024; save() }), in: Device.memoryChoices)
                        .font(.system(size: 16))
                    if let note = Device.memoryNote(mac.ramMB / 1024) {
                        Text(note).font(.system(size: 13)).foregroundStyle(Desk.dim)
                    }
                }
                .padding(17)
                .deskCard()

                DeskHeading("Processors")
                Stepper(value: $cpus, in: 1...6) {
                    HStack {
                        Text("CPUs").font(.system(size: 16))
                        Spacer()
                        Text("\(cpus)").font(.system(size: 16, weight: .semibold))
                    }
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 10)
                .deskCard()

                DeskHeading("Apple Account")
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppleAccountSupport.status(identityPresent: mac.activeSoftwareIdentity != nil, nativeStatus: nil))
                    NavigationLink("Apple Account & App Store") {
                        AppleAccountSetupView(macID: mac.id)
                    }
                    Text("Set up a compatible Mac or check what this Mac needs for account sign-in.")
                        .font(.footnote).foregroundStyle(Desk.dim)
                }
                .padding(17)
                .deskCard()

                DeskHeading("About This Mac")
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(get: { mac.reportHostIdentity ?? false }, set: {
                        mac.reportHostIdentity = $0
                        if !$0 { mac.reportHostModelID = false }
                        save()
                    })) {
                        Text("Report this \(Device.name)").font(.system(size: 16))
                    }
                    Text("The Mac says it is \(Device.marketingName)\(Device.chipName.map { " with the \($0) chip" } ?? ""). Changes apply the next time this Mac starts.")
                        .font(.system(size: 13)).foregroundStyle(Desk.dim)
                    if mac.reportHostIdentity == true {
                        Toggle(isOn: Binding(get: { mac.reportHostModelID ?? false }, set: { mac.reportHostModelID = $0; save() })) {
                            Text("Also report a model identifier").font(.system(size: 16))
                        }
                        Text("Reports \(Device.snappedModelIdentifier(forOS: mac.osName)) so this Mac shows a matching icon; the name stays \(Device.marketingName). Snaps to the newest \(Device.name) this macOS recognises. Experimental: macOS keys some hardware decisions off the model.")
                            .font(.system(size: 13)).foregroundStyle(Desk.dim)
                    }
                }
                .padding(17)
                .deskCard()

                DeskHeading("Screen")
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Resolution", selection: Binding(get: {
                        if mac.customResolution == true { return "custom" }
                        if mac.isRetina { return "retina" }
                        if mac.screen.width == 2560, mac.screen.height == 1440 { return "qhd" }
                        if mac.screen.width == Device.performanceScreen.width,
                           mac.screen.height == Device.performanceScreen.height { return "performance" }
                        if mac.screen.width == 1920, mac.screen.height == 1080 { return "wide" }
                        return "fit"
                    }, set: { choice in
                        if choice == "custom" {
                            let current = mac.screen
                            let size = current
                            mac.retina = false
                            mac.customResolution = true
                            (mac.screenWidth, mac.screenHeight) = size
                            customWidth = String(size.width)
                            customHeight = String(size.height)
                        } else {
                            mac.retina = choice == "retina"
                            mac.customResolution = false
                            switch choice {
                            case "retina": break
                            case "performance": (mac.screenWidth, mac.screenHeight) = Device.performanceScreen
                            case "wide": (mac.screenWidth, mac.screenHeight) = (1920, 1080)
                            case "qhd": (mac.screenWidth, mac.screenHeight) = (2560, 1440)
                            default: (mac.screenWidth, mac.screenHeight) = Device.fittingScreen
                            }
                        }
                        save()
                    })) {
                        if Device.isPad {
                            Text("Retina").tag("retina")
                            Text("Performance").tag("performance")
                        }
                        Text("Fit this \(Device.name)").tag("fit")
                        Text("1920 × 1080 (Full HD)").tag("wide")
                        Text("2560 × 1440 (QHD / 2K)").tag("qhd")
                        Text("Custom").tag("custom")
                    }
                    .pickerStyle(.menu)

                    if mac.customResolution == true {
                        HStack(spacing: 12) {
                            TextField("Width", text: $customWidth)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Custom screen width in pixels")
                            Text("×").foregroundStyle(Desk.dim)
                            TextField("Height", text: $customHeight)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Custom screen height in pixels")
                        }
                        if validCustomResolution == nil {
                            Text("Enter 640–7680 × 480–4320 pixels, up to 8.3 million pixels.")
                                .font(.system(size: 13)).foregroundStyle(Desk.bad)
                        } else {
                            Text("Valid sizes are saved automatically.")
                                .font(.footnote).foregroundStyle(Desk.dim)
                        }
                    }

                    Text("\(mac.screen.width) × \(mac.screen.height) pixels. Shut down macOS and start it again to apply; resuming a running Mac keeps its current display.")
                        .font(.system(size: 13)).foregroundStyle(Desk.dim)
                }

                DeskHeading("Storage")
                VStack(spacing: 11) {
                    HStack {
                        Text("\(ByteText.string(UInt64(max(mac.bytesUsed, 0)))) used").font(.system(size: 16))
                        Spacer()
                        Text("of \(ByteText.string(UInt64(max(mac.diskBytes, 0))))").font(.system(size: 16)).foregroundStyle(Desk.dim)
                    }
                    DeskBar(fraction: Double(mac.bytesUsed) / Double(max(mac.diskBytes, 1)))
                }
                .padding(17)
                .deskCard()

                DeskHeading("Manage")
                manage
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .deskColumn()
        }
        .background(Desk.page)
        .navigationTitle(mac.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let current = machines.all.first(where: { $0.id == mac.id }) { mac = current }
        }
        .onChange(of: customWidth) { _ in saveValidCustomDraft() }
        .onChange(of: customHeight) { _ in saveValidCustomDraft() }
        .onDisappear(perform: save)
        .fileMover(isPresented: $movingExport, file: machines.lastExport) { result in
            switch result {
            case .success: machines.lastExport = nil
            case .failure(let error): machines.lastError = error.localizedDescription
            }
        }
        .confirmationDialog("Delete \(mac.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                machines.delete(mac.id)
                dismiss()
            }
        } message: {
            Text("Its disk is removed from this \(Device.name).")
        }
    }

    private var manage: some View {
        VStack(spacing: 0) {
            if let name = machines.exporting {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Exporting \(name)… keep Henge open").font(.system(size: 15))
                    DeskBar(fraction: machines.exported)
                }
                .padding(17)
            } else {
                row("Export", symbol: "square.and.arrow.up", tint: Desk.accentLight) { machines.export(mac) }
            }
            if let folder = machines.lastExport {
                divider
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved in Files, under Henge, Exports, \(folder.lastPathComponent). Deleting Henge deletes it too, so move it somewhere else first.")
                        .font(.system(size: 13)).foregroundStyle(Desk.dim)
                    Button("Move Out of Henge…") { movingExport = true }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Desk.accentLight)
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            divider
            row("Delete this Mac", symbol: nil, tint: Desk.bad) { confirmDelete = true }
        }
        .deskCard()
    }

    private var divider: some View { Rectangle().fill(Desk.hairline).frame(height: 0.5) }

    private func row(_ title: String, symbol: String?, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 16)).foregroundStyle(tint)
                Spacer()
                if let symbol { Image(systemName: symbol).foregroundStyle(tint) }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }

    /// Invalid drafts are not saved to guest configuration.
    private var validCustomResolution: GuestResolution? {
        GuestResolution(width: customWidth, height: customHeight)
    }

    private func saveValidCustomDraft() {
        guard mac.customResolution == true, validCustomResolution != nil else { return }
        save()
    }

    private func save() {
        if mac.customResolution == true, let size = validCustomResolution {
            mac.retina = false
            (mac.screenWidth, mac.screenHeight) = (size.width, size.height)
        }
        if mac.name.isEmpty { mac.name = "Mac" }
        machines.update(mac)
    }
}
