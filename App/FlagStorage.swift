import Darwin
import Foundation

enum FlagStorage {
  static let preferences = "/private/var/preferences"
  static let featureDirectory = "\(preferences)/FeatureFlags"
  static let domainDirectory = "\(featureDirectory)/Domain"
  private static let directories = [preferences, featureDirectory, domainDirectory]
  private static let fm = FileManager.default

  private static var receiptDirectory: URL {
    fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("OwnershipReceipts", isDirectory: true)
  }

  private static func receipt(for path: String) throws -> URL {
    guard let index = directories.firstIndex(of: path) else {
      throw FlagError("Unapproved ownership target")
    }
    return receiptDirectory.appendingPathComponent("directory-\(index).plist")
  }

  static var hasOwnershipReceipts: Bool {
    directories.contains { path in
      guard let url = try? receipt(for: path) else { return false }
      return fm.fileExists(atPath: url.path)
    }
  }

  private static func info(_ path: String, directory: Bool) throws -> stat? {
    var value = stat()
    if path.withCString({ lstat($0, &value) }) == 0 {
      let expected: mode_t = directory ? 0o040000 : 0o100000
      guard value.st_mode & 0o170000 == expected else {
        throw FlagError("Unexpected file type at \(path)")
      }
      return value
    }
    if errno == ENOENT { return nil }
    throw FlagError("Cannot inspect \(path): errno \(errno)")
  }

  private static func requiredDirectory(_ path: String) throws -> stat {
    guard let value = try info(path, directory: true) else {
      throw FlagError("Directory is missing: \(path)")
    }
    return value
  }

  private static func readFile(_ path: String) throws -> Data? {
    guard let value = try info(path, directory: false) else { return nil }
    guard value.st_size >= 0 && value.st_size <= 1_048_576 else {
      throw FlagError("Feature flag plist has an unexpected size at \(path)")
    }
    return try Data(contentsOf: URL(fileURLWithPath: path))
  }

  static func readOverrides() throws -> [String: Data] {
    guard try info(domainDirectory, directory: true) != nil else { return [:] }
    let names = try fm.contentsOfDirectory(atPath: domainDirectory)
    var result: [String: Data] = [:]
    for file in names where file.hasSuffix(".plist") {
      let domain = String(file.dropLast(6))
      guard FlagCatalog.validComponent(domain) else { continue }
      if let data = try readFile("\(domainDirectory)/\(file)") {
        _ = try FlagCatalog.parseDomain(data)
        result[domain] = data
      }
    }
    return result
  }

  private static func withDirectoryOwner<T>(_ path: String, work: () throws -> T) throws -> T {
    let original = try requiredDirectory(path)
    if original.st_uid == getuid() { return try work() }
    var volume = statfs()
    guard path.withCString({ statfs($0, &volume) }) == 0,
      volume.f_flags & UInt32(MNT_RDONLY) == 0
    else { throw FlagError("Feature flag directory is read only: \(path)") }

    try fm.createDirectory(
      at: receiptDirectory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let receipt = try receipt(for: path)
    guard !fm.fileExists(atPath: receipt.path) else {
      throw FlagError("Repair the saved ownership receipt before writing")
    }
    let values: [String: NSNumber] = [
      "uid": NSNumber(value: original.st_uid),
      "gid": NSNumber(value: original.st_gid),
    ]
    try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
      .write(to: receipt, options: .atomic)
    guard path.withCString({ apfs_own($0, getuid(), original.st_gid) == 0 }) else {
      if let unchanged = try? requiredDirectory(path),
        unchanged.st_uid == original.st_uid, unchanged.st_gid == original.st_gid
      {
        try? fm.removeItem(at: receipt)
      }
      throw FlagError("Could not temporarily own \(path)")
    }
    let result: Result<T, Error>
    do { result = .success(try work()) } catch { result = .failure(error) }
    guard path.withCString({ apfs_own($0, original.st_uid, original.st_gid) == 0 }),
      let restored = try? requiredDirectory(path),
      restored.st_uid == original.st_uid, restored.st_gid == original.st_gid
    else { throw FlagError("Could not restore owner of \(path); receipt retained") }
    try fm.removeItem(at: receipt)
    return try result.get()
  }

  static func repairOwnership() throws {
    for path in directories {
      let receipt = try receipt(for: path)
      guard fm.fileExists(atPath: receipt.path) else { continue }
      let data = try Data(contentsOf: receipt)
      guard let values = try PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: NSNumber],
        let uid = values["uid"]?.uint32Value,
        let gid = values["gid"]?.uint32Value
      else { throw FlagError("Invalid ownership receipt for \(path)") }
      _ = try requiredDirectory(path)
      guard path.withCString({ apfs_own($0, uid, gid) == 0 }),
        let restored = try? requiredDirectory(path),
        restored.st_uid == uid, restored.st_gid == gid
      else { throw FlagError("Could not repair owner of \(path)") }
      try fm.removeItem(at: receipt)
    }
  }

  private static func ensureDirectories() throws {
    _ = try requiredDirectory(preferences)
    for (path, parent) in [
      (featureDirectory, preferences),
      (domainDirectory, featureDirectory),
    ] {
      if try info(path, directory: true) != nil { continue }
      let parentInfo = try requiredDirectory(parent)
      try withDirectoryOwner(parent) {
        try fm.createDirectory(
          atPath: path, withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o755])
        guard path.withCString({ apfs_own($0, parentInfo.st_uid, parentInfo.st_gid) == 0 }) else {
          try? fm.removeItem(atPath: path)
          throw FlagError("Could not set owner of new directory \(path)")
        }
      }
    }
  }

  static func update(_ id: FlagID, expected: Data?, enabled: Bool?) throws {
    guard DeviceGate.isSupported, FlagCatalog.validComponent(id.domain),
      FlagCatalog.validFlagName(id.name)
    else { throw FlagError("Device or flag is not admitted") }
    guard !hasOwnershipReceipts else {
      throw FlagError("Repair ownership before changing a flag")
    }
    let target = "\(domainDirectory)/\(id.domain).plist"
    let current = try readFile(target)
    guard current == expected else {
      throw FlagError("\(id.domain) changed since the last refresh; reload before editing")
    }
    var dictionary = try current.map(FlagCatalog.parseDomain) ?? [:]
    var fields = dictionary[id.name] ?? [:]
    if let existing = fields["Enabled"], FlagCatalog.bool(existing) == nil {
      throw FlagError("Existing Enabled value is not Boolean")
    }
    if FlagCatalog.bool(fields["Enabled"]) == enabled { return }
    if let enabled {
      fields["Enabled"] = enabled
    } else {
      fields.removeValue(forKey: "Enabled")
    }
    if fields.isEmpty { dictionary.removeValue(forKey: id.name) }
    else { dictionary[id.name] = fields }
    guard PropertyListSerialization.propertyList(dictionary, isValidFor: .binary) else {
      throw FlagError("Edited domain plist is invalid")
    }
    let staged = try PropertyListSerialization.data(
      fromPropertyList: dictionary, format: .binary, options: 0)
    if staged == current { return }
    try ensureDirectories()
    let owner = try info(target, directory: false) ?? requiredDirectory(domainDirectory)
    let mode: mode_t = current == nil ? 0o644 : (owner.st_mode & 0o777)
    guard mode & 0o444 != 0 else {
      throw FlagError("Cannot verify a non-readable override file")
    }
    try withDirectoryOwner(domainDirectory) {
      guard try readFile(target) == current else {
        throw FlagError("\(id.domain) changed during the write")
      }
      let temporary = "\(domainDirectory)/.\(id.domain).\(UUID().uuidString).tmp"
      let fd = temporary.withCString { open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) }
      guard fd >= 0 else { throw FlagError("Could not create staging file: errno \(errno)") }
      defer { temporary.withCString { _ = unlink($0) } }
      var offset = 0
      let writeResult = staged.withUnsafeBytes { bytes -> Bool in
        guard let base = bytes.baseAddress else { return false }
        while offset < bytes.count {
          let amount = write(fd, base.advanced(by: offset), bytes.count - offset)
          if amount <= 0 { return false }
          offset += amount
        }
        return true
      }
      guard writeResult, fchmod(fd, mode) == 0, fsync(fd) == 0 else {
        _ = close(fd)
        throw FlagError("Could not finish staging file: errno \(errno)")
      }
      guard close(fd) == 0 else { throw FlagError("Could not close staging file") }
      guard temporary.withCString({ apfs_own($0, owner.st_uid, owner.st_gid) == 0 }) else {
        throw FlagError("Could not preserve override file ownership")
      }
      guard temporary.withCString({ source in target.withCString { rename(source, $0) } }) == 0
      else { throw FlagError("Could not replace override file: errno \(errno)") }
      let directoryFD = domainDirectory.withCString { open($0, O_RDONLY) }
      if directoryFD >= 0 { _ = fsync(directoryFD); _ = close(directoryFD) }
      guard try readFile(target) == staged else {
        throw FlagError("Override readback differs for \(id.domain)")
      }
    }
  }
}
