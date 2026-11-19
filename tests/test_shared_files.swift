import Foundation

@main struct SharedFileTests {
    static func main() throws {
        func check(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
            let passed = try value()
            precondition(passed, message, file: file, line: line)
        }
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("henge-file-test-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("example.txt")
        let bytes = Data((0..<65536).map { UInt8(truncatingIfNeeded: $0) })
        try bytes.write(to: source)
        let store = SharedFileStore(root: temporary.appendingPathComponent("Shared", isDirectory: true))
        let first = try store.importFile(source)
        let second = try store.importFile(source)
        precondition(first.lastPathComponent == "example.txt" && second.lastPathComponent == "example 2.txt")
        try check(Data(contentsOf: first) == bytes)
        try check(Data(contentsOf: second) == bytes)
        precondition(fm.fileExists(atPath: source.path), "a drop copies rather than moving the source")
        try check(store.importFile(first) == first, "dropping an already shared file never copies a folder into itself")
        try check(store.importFile(first, into: store.root) == first, "explicit root drops preserve canonical paths")
        func refused(_ body: () throws -> Void) {
            do { try body(); fatalError("unsafe transfer was accepted") } catch { }
        }
        refused { _ = try store.importFile(URL(string: "https://example.com/file")!) }
        refused { _ = try store.importFile(source, preferredName: "../escape") }
        refused { _ = try store.importFile(source, preferredName: ".henge-put-private") }
        refused { _ = try store.importFile(temporary) }
        refused { _ = try store.exportCopy(source) }
        refused { _ = try store.exportCopy(store.root) }
        refused { _ = try store.entries(in: temporary) }
        let folder = temporary.appendingPathComponent("Folder", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("Unicode file".utf8).write(to: folder.appendingPathComponent("файл.txt"))
        let copiedFolder = try store.importFile(folder)
        try check(store.entries(in: copiedFolder).map(\.name) == ["файл.txt"])
        let nested = try store.importFile(source, into: copiedFolder)
        try check(nested.deletingLastPathComponent() == copiedFolder,
                  "nested parent \(nested.deletingLastPathComponent().absoluteString) != imported folder \(copiedFolder.absoluteString)")
        try check(store.importFile(nested, into: copiedFolder) == nested, "an in-folder drop is idempotent even through /var path aliases")
        refused { _ = try store.importFile(source, into: temporary) }
        let link = folder.appendingPathComponent("outside-link")
        try fm.createSymbolicLink(at: link, withDestinationURL: source)
        refused { _ = try store.importFile(folder) }
        let guestLink = store.root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: guestLink, withDestinationURL: source)
        refused { _ = try store.exportCopy(guestLink) }
        try check(!store.entries().contains { $0.name == "link" })
        let exported = try store.exportCopy(first)
        defer { try? fm.removeItem(at: exported.deletingLastPathComponent()) }
        try Data("later guest edit".utf8).write(to: first)
        try check(Data(contentsOf: exported) == bytes, "outbound file promises retain an independent copy")
        try check(Data(contentsOf: source) == bytes)
        print("PASS: file bytes, source preservation, collision copies, folders, provider lifetime and path/link containment")
    }
}
