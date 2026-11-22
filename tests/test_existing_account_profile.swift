import Foundation

@main struct ExistingAccountProfileTests {
    static func main() throws {
        func check(_ condition: Bool, _ message: String = "check failed") { precondition(condition, message) }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let id = UUID(), ecid: UInt64 = 12345, seed: UInt64 = 67890
        let originals = ["disk.img": Data("installed Ventura and user files".utf8),
                         "auxiliary.bin": Data("existing NVRAM".utf8),
                         "AVPBooter.vmapple2.bin": Data("existing ROM".utf8),
                         "machine.json": Data("original manifest".utf8)]
        for (name, data) in originals { try data.write(to: root.appendingPathComponent(name)) }
        func read() throws -> ExistingAccountProfile? { try ExistingAccountProfile.read(in: root, machineID: id, ecid: ecid, seed: seed) }
        func change(_ on: Bool, canChange: Bool = true, identity: SoftwareIdentity? = nil) throws -> ExistingAccountProfile {
            try ExistingAccountProfile.setEnabled(on, in: root, machineID: id, ecid: ecid, seed: seed, identity: identity, canChange: canChange)
        }
        func rejects(_ body: () throws -> Void) {
            do { try body(); preconditionFailure("operation should have been rejected") }
            catch { check(!error.localizedDescription.isEmpty) }
        }
        check(try read() == nil)
        rejects { _ = try change(true, canChange: false) }
        check(try read() == nil)
        for name in ["resume.hsnap", "resume.hsnap.part"] {
            let file = root.appendingPathComponent(name)
            let memory = Data("unsaved user work".utf8)
            try memory.write(to: file)
            rejects { _ = try change(true) }
            check(try Data(contentsOf: file) == memory)
            check(try read() == nil)
            try fm.removeItem(at: file)
        }
        let enabled = try change(true)
        check(enabled.enabled && enabled.identity.isValid)
        check(try read() == enabled) // durable independently of the machines list
        let off = try change(false)
        check(!off.enabled && off.identity == enabled.identity)
        let on = try change(true, identity: SoftwareIdentity.make())
        check(on == enabled, "re-enabling ignores stale/different caller identity")
        for (name, data) in originals { check(try Data(contentsOf: root.appendingPathComponent(name)) == data) }
        let names = Set(try fm.contentsOfDirectory(atPath: root.path))
        check(names == Set(originals.keys).union([ExistingAccountProfile.filename]), "only the sidecar was added")

        // Wrong-machine profiles and corrupt records never rotate or overwrite identity.
        let file = root.appendingPathComponent(ExistingAccountProfile.filename)
        let validData = try Data(contentsOf: file)
        rejects { _ = try ExistingAccountProfile.read(in: root, machineID: UUID(), ecid: ecid, seed: seed) }
        rejects { _ = try ExistingAccountProfile.read(in: root, machineID: id, ecid: ecid + 1, seed: seed) }
        rejects { _ = try ExistingAccountProfile.read(in: root, machineID: id, ecid: ecid, seed: seed + 1) }
        for corrupt in [Data("broken JSON".utf8), try JSONEncoder().encode(ExistingAccountProfile(version: 99, machineID: id, ecid: ecid, seed: seed, identity: enabled.identity, enabled: true))] {
            try corrupt.write(to: file)
            rejects { _ = try read() }
            rejects { _ = try change(true) }
            check(try Data(contentsOf: file) == corrupt)
        }
        try validData.write(to: file)
        // An unreadable target is rejected without deleting or replacing it.
        // A directory at the target path makes this deterministic even as root.
        try fm.removeItem(at: file)
        try fm.createDirectory(at: file, withIntermediateDirectories: false)
        rejects { _ = try change(false) }
        check(fm.fileExists(atPath: file.path))
        try fm.removeItem(at: file)
        // A previously-created profile is adopted exactly, never regenerated.
        let existing = SoftwareIdentity.make()
        let adopted = try change(true, identity: existing)
        check(adopted.identity == existing)
        try fm.removeItem(at: file)
        var invalid = existing; invalid.serial = "bad"
        rejects { _ = try change(true, identity: invalid) }
        check(try read() == nil)
        let missing = root.appendingPathComponent("missing")
        rejects { _ = try ExistingAccountProfile.setEnabled(true, in: missing, machineID: id, ecid: ecid, seed: seed, identity: nil, canChange: true) }
        check(!fm.fileExists(atPath: missing.path))
        print("PASS: installed-Mac profile persistence, stable re-enable, rollback, snapshot/running guards, unchanged guest files, invalid-profile rejection")
    }
}
