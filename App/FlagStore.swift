import Combine
import Foundation

@MainActor
final class FlagStore: ObservableObject {
  @Published private(set) var records: [FlagRecord] = []
  @Published private(set) var message = "Loading the feature flag catalog…"
  @Published private(set) var liveDomainCount = 0
  @Published private(set) var isBusy = false
  @Published private(set) var needsOwnershipRepair = false

  private struct Snapshot { let data: Data? }
  private var snapshots: [String: Snapshot] = [:]

  func refresh() {
    do {
      let (definitions, liveCount) = FlagCatalog.load()
      liveDomainCount = liveCount
      let canReadOverrides = AccessController.shared.isReady && DeviceGate.isSupported
      let overrideFiles = canReadOverrides ? try FlagStorage.readOverrides() : [:]
      var parsedOverrides: [String: [String: [String: Any]]] = [:]
      for (domain, data) in overrideFiles {
        parsedOverrides[domain] = try FlagCatalog.parseDomain(data)
      }
      snapshots = overrideFiles.mapValues { Snapshot(data: $0) }
      let allDomains = Set(definitions.keys).union(parsedOverrides.keys)
      var result: [FlagRecord] = []
      for domain in allDomains.sorted() {
        let source = definitions[domain] ?? [:]
        let overrides = parsedOverrides[domain] ?? [:]
        for name in Set(source.keys).union(overrides.keys).sorted() {
          let sourceFields = source[name] ?? [:]
          let overrideFields = overrides[name] ?? [:]
          let state: OverrideState
          if !canReadOverrides { state = .unread }
          else if let value = FlagCatalog.bool(overrideFields["Enabled"]) {
            state = value ? .on : .off
          } else { state = .inherited }
          result.append(FlagRecord(
            key: FlagID(domain: domain, name: name),
            defaultEnabled: FlagCatalog.bool(sourceFields["Enabled"]),
            developmentPhase: sourceFields["DevelopmentPhase"] as? String,
            override: state,
            isDefinedBySystem: source[name] != nil))
        }
      }
      records = result
      needsOwnershipRepair = FlagStorage.hasOwnershipReceipts
      if !DeviceGate.isSupported {
        message = DeviceGate.unsupportedReason ?? "This device is not supported."
      } else if needsOwnershipRepair {
        message = "A directory ownership receipt needs repair before any flag can change."
      } else if !canReadOverrides {
        message = "Catalog loaded. Prepare access to read and change overrides."
      } else {
        message = "\(result.count) flags across \(allDomains.count) domains. Restart affected apps or the device after changing a flag."
      }
    } catch {
      records = []
      snapshots = [:]
      message = "Refresh failed: \(error.localizedDescription)"
    }
  }

  func set(_ id: FlagID, enabled: Bool?) {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      guard AccessController.shared.isReady else { throw FlagError("Prepare access first") }
      guard records.contains(where: { $0.key == id }) else {
        throw FlagError("Flag is not in the current catalog")
      }
      try FlagStorage.update(id, expected: snapshots[id.domain]?.data, enabled: enabled)
      refresh()
      message = "\(id.domain)/\(id.name): \(enabled.map { $0 ? "forced on" : "forced off" } ?? "using default")."
    } catch {
      refresh()
      message = "Change failed: \(error.localizedDescription)"
    }
  }

  func repairOwnership() {
    guard AccessController.shared.isReady else {
      message = "Prepare access before repairing ownership."
      return
    }
    do {
      try FlagStorage.repairOwnership()
      refresh()
      message = "Directory ownership restored."
    } catch {
      refresh()
      message = "Ownership repair failed: \(error.localizedDescription)"
    }
  }
}
