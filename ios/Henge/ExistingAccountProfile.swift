import Foundation

/// An opt-in hardware profile for an installed Mac. One atomic file is the
/// commit point: no guest filesystem, NVRAM, ECID or seed is edited by this code.
struct ExistingAccountProfile: Codable, Equatable {
    var version = 1
    var machineID: UUID
    var ecid: UInt64
    var seed: UInt64
    var identity: SoftwareIdentity
    var enabled: Bool

    static let filename = "account-profile.json"

    static func read(in directory: URL, machineID: UUID, ecid: UInt64, seed: UInt64) throws -> Self? {
        let file = directory.appendingPathComponent(filename)
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        catch { throw failure("The saved account profile could not be read. No replacement identity was generated.") }
        guard let profile = try? JSONDecoder().decode(Self.self, from: data),
              profile.version == 1, profile.machineID == machineID,
              profile.ecid == ecid, profile.seed == seed, profile.identity.isValid else {
            throw failure("The saved account profile is invalid or belongs to a different Mac. No replacement identity was generated.")
        }
        return profile
    }

    static func hasSavedSession(in directory: URL) -> Bool {
        ["resume.hsnap", "resume.hsnap.part"].contains {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool, in directory: URL, machineID: UUID,
                           ecid: UInt64, seed: UInt64, identity: SoftwareIdentity?,
                           canChange: Bool) throws -> Self {
        guard canChange else { throw failure("Shut down the Mac and wait for installation, import or export to finish before changing its account profile.") }
        guard !hasSavedSession(in: directory) else {
            throw failure("This Mac has a saved memory session. Start it and choose Shut Down from the Apple menu, then try again. Its saved session has been kept.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw failure("This Mac's folder is unavailable. Its account profile was not changed.")
        }
        let stored = try read(in: directory, machineID: machineID, ecid: ecid, seed: seed)
        // Keep both old version-1 profiles and disabled profiles byte-for-byte.
        // Re-enabling must never silently create another device identity.
        let chosen = stored?.identity ?? identity ?? SoftwareIdentity.make()
        guard chosen.isValid else { throw failure("This Mac's software identity is invalid.") }
        var profile = Self(machineID: machineID, ecid: ecid, seed: seed, identity: chosen, enabled: enabled)
        if let stored { profile = stored; profile.enabled = enabled }
        let data = try JSONEncoder().encode(profile)
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        return profile
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Henge.AccountProfile", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
