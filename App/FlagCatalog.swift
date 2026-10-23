import CoreFoundation
import Foundation

struct FlagID: Hashable {
  let domain: String
  let name: String
}

enum OverrideState: Equatable {
  case unread
  case inherited
  case on
  case off

  var label: String {
    switch self {
    case .unread: return "Override not read"
    case .inherited: return "Use default"
    case .on: return "Forced on"
    case .off: return "Forced off"
    }
  }
}

struct FlagRecord: Identifiable {
  let key: FlagID
  let defaultEnabled: Bool?
  let developmentPhase: String?
  let override: OverrideState
  let isDefinedBySystem: Bool

  var id: String { "\(key.domain)/\(key.name)" }
  var defaultLabel: String {
    if let defaultEnabled { return defaultEnabled ? "On" : "Off" }
    return "Unspecified"
  }
}

enum FlagCatalog {
  typealias Definitions = [String: [String: [String: Any]]]
  static let systemDirectory = "/System/Library/FeatureFlags/Domain"

  static func validComponent(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && name.utf8.count <= 200
      && name.utf8.allSatisfy {
        ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122)
          || ($0 >= 48 && $0 <= 57) || $0 == 45 || $0 == 46 || $0 == 95
      }
  }

  static func validFlagName(_ name: String) -> Bool {
    !name.isEmpty && name.utf8.count <= 512
      && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
  }

  static func bool(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber,
      CFGetTypeID(number) == CFBooleanGetTypeID()
    else { return nil }
    return number.boolValue
  }

  static func parseDomain(_ data: Data) throws -> [String: [String: Any]] {
    guard data.count <= 1_048_576,
      let root = try PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else { throw FlagError("Invalid feature flag domain plist") }
    var result: [String: [String: Any]] = [:]
    for (name, value) in root {
      guard validFlagName(name), let fields = value as? [String: Any] else {
        throw FlagError("Invalid flag entry \(name)")
      }
      result[name] = fields
    }
    return result
  }

  static func load() -> (definitions: Definitions, liveCount: Int) {
    var definitions: Definitions = [:]
    var liveCount = 0
    if let names = try? FileManager.default.contentsOfDirectory(atPath: systemDirectory) {
      for file in names where file.hasSuffix(".plist") {
        let domain = String(file.dropLast(6))
        guard validComponent(domain) else { continue }
        let path = "\(systemDirectory)/\(file)"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let entries = try? parseDomain(data)
        else { continue }
        definitions[domain] = entries
        liveCount += 1
      }
    }
    return (definitions, liveCount)
  }
}

struct FlagError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}
