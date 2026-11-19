import Foundation

/// Copies file representations while their provider URL is still valid. No
/// bytes are loaded into a Swift Data buffer and existing files are never replaced.
final class SharedFileStore: @unchecked Sendable {
    struct Entry: Identifiable, Sendable {
        let url: URL
        let isDirectory: Bool
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }
    enum Failure: LocalizedError {
        case notFile, unsupported, recursive, invalidName, outsideShared, tooManyNames
        var errorDescription: String? {
            switch self {
            case .notFile: return "Drop a local file or folder. Web links are not downloaded."
            case .unsupported: return "Symbolic links and special files cannot be transferred."
            case .recursive: return "A folder cannot be copied into itself."
            case .invalidName: return "This file name is reserved or invalid."
            case .outsideShared: return "Only files in the Shared folder can be exported."
            case .tooManyNames: return "A free destination name could not be found."
            }
        }
    }

    let root: URL
    private let lock = NSLock()
    private let fm = FileManager.default

    init(root: URL) { self.root = root.standardizedFileURL }

    private func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
            && !name.contains("\0") && name != ".henge" && !name.hasPrefix(".henge-")
    }

    private func checkedRoot() throws -> URL {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let values = try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else { throw Failure.unsupported }
        return root.resolvingSymlinksInPath().standardizedFileURL
    }

    private func inside(_ file: URL, _ directory: URL) -> Bool {
        file.path == directory.path || file.path.hasPrefix(directory.path + "/")
    }

    /// Reject links throughout a directory, rather than letting a later provider
    /// follow a link to a file the person never selected.
    private func checkTree(_ url: URL) throws -> Bool {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        func check(_ item: URL) throws -> Bool {
            let v = try item.resourceValues(forKeys: keys)
            guard v.isSymbolicLink != true, v.isRegularFile == true || v.isDirectory == true else { throw Failure.unsupported }
            return v.isDirectory == true
        }
        let directory = try check(url)
        if directory {
            var enumerationError: Error?
            guard let items = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in
                enumerationError = error
                return false
            }) else { throw Failure.unsupported }
            for case let item as URL in items { _ = try check(item) }
            if let enumerationError { throw enumerationError }
        }
        return directory
    }

    func importFile(_ source: URL, preferredName: String? = nil, into directory: URL? = nil) throws -> URL {
        guard source.isFileURL else { throw Failure.notFile }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        lock.lock(); defer { lock.unlock() }
        let shared = try checkedRoot()
        let requested = (directory ?? shared).standardizedFileURL
        let folder = requested.resolvingSymlinksInPath().standardizedFileURL
        guard inside(folder, shared) else { throw Failure.outsideShared }
        let values = try requested.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.unsupported }
        let original = source.standardizedFileURL
        var result: URL?
        var operationError: Error?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: original, options: .withoutChanges, error: &coordinationError) { reading in
            do {
                let directory = try checkTree(reading)
                let canonical = reading.resolvingSymlinksInPath().standardizedFileURL
                if canonical.deletingLastPathComponent() == folder { result = canonical; return }
                guard !inside(folder, canonical) else { throw Failure.recursive }
                let name = preferredName ?? original.lastPathComponent
                guard validName(name) else { throw Failure.invalidName }
                let staging = fm.temporaryDirectory.appendingPathComponent("Henge-import-" + UUID().uuidString, isDirectory: true)
                try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                defer { try? fm.removeItem(at: staging) }
                let copy = staging.appendingPathComponent(name)
                try fm.copyItem(at: reading, to: copy)
                let ext = directory ? "" : (name as NSString).pathExtension
                let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
                for suffix in 0..<10_000 {
                    let candidate = suffix == 0 ? name : stem + " \(suffix + 1)" + (ext.isEmpty ? "" : "." + ext)
                    let destination = folder.appendingPathComponent(candidate)
                    do {
                        try fm.moveItem(at: copy, to: destination)
                        result = destination
                        return
                    } catch {
                        if fm.fileExists(atPath: destination.path) { continue }
                        throw error
                    }
                }
                throw Failure.tooManyNames
            } catch { operationError = error }
        }
        if let operationError { throw operationError }
        if let coordinationError { throw coordinationError }
        guard let result else { throw Failure.unsupported }
        return result
    }

    func entries(in directory: URL? = nil) throws -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        let folder = try checkedRoot(), at = (directory ?? root).standardizedFileURL
        guard inside(at.resolvingSymlinksInPath(), folder) else { throw Failure.outsideShared }
        guard try at.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw Failure.unsupported }
        return try fm.contentsOfDirectory(at: at, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            .filter { validName($0.lastPathComponent) }
            .compactMap { url in
                let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard v.isSymbolicLink != true else { return nil }
                return Entry(url: url, isDirectory: v.isDirectory == true)
            }
            .sorted { a, b in a.isDirectory != b.isDirectory ? a.isDirectory : a.name.localizedStandardCompare(b.name) == .orderedAscending }
    }

    /// Keep a private immutable copy for the system's asynchronous file promise.
    /// The OS owns temporary-directory cleanup; no guest file is moved or deleted.
    func exportCopy(_ source: URL) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        let folder = try checkedRoot(), source = source.standardizedFileURL
        let canonical = source.resolvingSymlinksInPath().standardizedFileURL
        guard canonical != folder, inside(canonical, folder) else { throw Failure.outsideShared }
        _ = try checkTree(source)
        let staging = fm.temporaryDirectory.appendingPathComponent("Henge-export-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let target = staging.appendingPathComponent(source.lastPathComponent)
            try fm.copyItem(at: source, to: target)
            return target
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }
}
