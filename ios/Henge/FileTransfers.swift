import SwiftUI
import UniformTypeIdentifiers

/// NSItemProvider is not Sendable. Keep its load entry points on the UI actor,
/// including a file-promise retry requested by a background URL callback.
@MainActor
private final class FileRepresentationLoader {
    private let provider: NSItemProvider
    init(_ provider: NSItemProvider) { self.provider = provider }
    func load(_ type: String, completion: @escaping @Sendable (URL?, Error?) -> Void) {
        _ = provider.loadFileRepresentation(forTypeIdentifier: type, completionHandler: completion)
    }
}

@MainActor
final class FileTransfers: ObservableObject {
    @Published private(set) var pending = 0
    @Published private(set) var completed = 0
    @Published private(set) var revision = 0
    @Published var error: String?
    let store = SharedFileStore(root: Sharing.folder)
    private let work = DispatchQueue(label: "henge.file-transfers", qos: .utility)

    static let dropTypes = [UTType.fileURL, .data, .folder, .package]

    private static func representation(_ provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first {
            guard let type = UTType($0), !type.conforms(to: .url) else { return false }
            return type.conforms(to: .data) || type.conforms(to: .directory)
        }
    }

    func accept(_ providers: [NSItemProvider], into directory: URL? = nil) -> Bool {
        let accepted = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || Self.representation($0) != nil }
        guard !accepted.isEmpty else { return false }
        error = nil
        pending += accepted.count
        for provider in accepted {
            let store = store, suggested = provider.suggestedName
            let complete: @Sendable (Result<URL, Error>) -> Void = { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pending -= 1
                    switch result {
                    case .success: self.completed += 1; self.revision += 1
                    case .failure(let failure):
                        self.error = (failure as? SharedFileStore.Failure)?.errorDescription ?? "The file could not be copied. Check access and available storage."
                    }
                }
            }
            let finish: @Sendable (URL?, Error?) -> Void = { url, error in
                // Copy within the callback: the temporary representation expires
                // as soon as this returns. Never postpone its copy to the UI actor.
                if let url, error == nil { complete(Result { try store.importFile(url, preferredName: suggested, into: directory) }) }
                else { complete(.failure(error ?? CocoaError(.fileReadUnknown))) }
            }
            let representation = Self.representation(provider)
            // These methods start asynchronous loads. Start them on this actor;
            // do not transfer a non-Sendable NSItemProvider to our worker queue.
            // Provider callbacks still copy their temporary URL before returning.
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let loader = FileRepresentationLoader(provider)
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    let url: URL?
                    if let value = item as? URL { url = value }
                    else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else if let text = item as? String { url = URL(string: text) }
                    else { url = nil }
                    if let url, error == nil {
                        let result = Result { try store.importFile(url, preferredName: suggested, into: directory) }
                        if case .success = result { complete(result); return }
                        if representation == nil { complete(result); return }
                    }
                    // Cloud providers can vend a URL that is not readable by
                    // this process. Ask for a file promise before reporting failure.
                    if let representation {
                        Task { @MainActor in loader.load(representation, completion: finish) }
                    } else { finish(nil, error) }
                }
            } else if let type = representation {
                _ = provider.loadFileRepresentation(forTypeIdentifier: type, completionHandler: finish)
            }
        }
        return true
    }

    func provider(for entry: SharedFileStore.Entry) -> NSItemProvider {
        let type = entry.isDirectory ? UTType.folder : UTType(filenameExtension: entry.url.pathExtension) ?? .data
        let provider = NSItemProvider()
        provider.suggestedName = entry.name
        let store = store, work = work
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            let progress = Progress(totalUnitCount: 1)
            work.async {
                do {
                    guard !progress.isCancelled else { throw CocoaError(.userCancelled) }
                    let copy = try store.exportCopy(entry.url)
                    progress.completedUnitCount = 1
                    completion(copy, false, nil)
                } catch { completion(nil, false, error) }
            }
            return progress
        }
        return provider
    }
}

struct SharedFilesView: View {
    @ObservedObject var transfers: FileTransfers
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SharedFileFolder(transfers: transfers, directory: transfers.store.root)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct SharedFileFolder: View {
    @ObservedObject var transfers: FileTransfers
    let directory: URL
    @State private var entries: [SharedFileStore.Entry] = []
    @State private var listError: String?
    @State private var targeted = false

    var body: some View {
        List {
            Section {
                Text("Drop files here or on the Mac image. In macOS, use the Henge folder in your home folder. Copy guest files there, then drag them from this list to Files or another iPad app.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("If the guest folder is not mounted, use Finder → Go → Connect to Server and enter http://10.0.2.4/.")
                    .font(.footnote).foregroundStyle(.secondary)
                if transfers.pending > 0 { ProgressView("Copying \(transfers.pending) file(s)…") }
                if transfers.completed > 0 { Text("Copied \(transfers.completed) file(s) to Shared").font(.footnote) }
                if let error = transfers.error ?? listError { Text(error).foregroundStyle(.red) }
            }
            Section {
                if entries.isEmpty { Text("No files in this folder").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    if entry.isDirectory {
                        NavigationLink {
                            SharedFileFolder(transfers: transfers, directory: entry.url)
                        } label: { Label(entry.name, systemImage: "folder") }
                            .onDrag { transfers.provider(for: entry) }
                    } else {
                        Label(entry.name, systemImage: "doc")
                            .onDrag { transfers.provider(for: entry) }
                    }
                }
            }
        }
        .navigationTitle(directory == transfers.store.root ? "Shared Files" : directory.lastPathComponent)
        .onDrop(of: FileTransfers.dropTypes, isTargeted: $targeted) { transfers.accept($0, into: directory) }
        .overlay { if targeted { Rectangle().stroke(.tint, lineWidth: 2).allowsHitTesting(false) } }
        .refreshable { await refresh() }
        .task(id: transfers.revision) {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func refresh() async {
        let store = transfers.store, directory = directory
        let result = await Task.detached(priority: .utility) { Result { try store.entries(in: directory) } }.value
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let files): entries = files; listError = nil
        case .failure: listError = "This folder is unavailable. Refresh after the guest finishes writing it."
        }
    }
}
