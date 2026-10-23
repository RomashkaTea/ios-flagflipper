import Darwin
import Foundation

enum DeviceGate {
  static let supportedVersions = "iOS/iPadOS 17.0–18.7.1 or 26.0–26.0.1"

  static func sysctlString(_ name: String) -> String? {
    var size: size_t = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
    return String(cString: bytes)
  }

  static func supports(_ version: OperatingSystemVersion) -> Bool {
    switch version.majorVersion {
    case 17:
      return true
    case 18:
      return version.minorVersion < 7
        || (version.minorVersion == 7 && version.patchVersion <= 1)
    case 26:
      return version.minorVersion == 0 && version.patchVersion <= 1
    default:
      return false
    }
  }

  static func supports(machine: String) -> Bool {
    guard machine.hasPrefix("iPhone") || machine.hasPrefix("iPad") else { return false }
    // DarkSword cannot run on A19/A19 Pro or M5 devices because of MIE.
    return !machine.hasPrefix("iPhone18,") && !machine.hasPrefix("iPad17,")
  }

  static var unsupportedReason: String? {
    guard let machine = sysctlString("hw.machine"),
      machine.hasPrefix("iPhone") || machine.hasPrefix("iPad")
    else {
      return "FlagFlipper requires a physical iPhone or iPad."
    }
    guard supports(machine: machine) else {
      return "This device is not supported by DarkSword (A19/A19 Pro and M5 are excluded)."
    }
    guard supports(ProcessInfo.processInfo.operatingSystemVersion) else {
      return "This OS version is not supported. Use \(supportedVersions)."
    }
    return nil
  }

  static var isSupported: Bool { unsupportedReason == nil }
}
