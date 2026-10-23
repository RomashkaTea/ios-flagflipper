import SwiftUI

struct FlagFlipperView: View {
  @ObservedObject private var access = AccessController.shared
  @StateObject private var store = FlagStore()
  @State private var search = ""
  @State private var changedOnly = false

  private var visible: [FlagRecord] {
    store.records.filter { record in
      (!changedOnly || record.override == .on || record.override == .off)
        && (search.isEmpty || record.key.domain.localizedCaseInsensitiveContains(search)
          || record.key.name.localizedCaseInsensitiveContains(search))
    }
  }

  var body: some View {
    List {
      Section {
        Text(store.message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        if !access.isReady {
          Button("Prepare Access") { access.prepare() }
            .disabled(access.isWorking || !DeviceGate.isSupported)
          if access.isWorking { ProgressView(value: access.progress) }
          Text(access.message).font(.caption).foregroundStyle(.secondary)
        }
        if store.needsOwnershipRepair {
          Button("Repair Directory Ownership") { store.repairOwnership() }
            .disabled(!access.isReady)
        }
        Toggle("Show forced values only", isOn: $changedOnly)
      } header: {
        Text("FlagFlipper")
      } footer: {
        Text("System definitions: \(store.liveDomainCount) live domains. An unspecified default is not an effective-state reading.")
      }

      Section("Flags (\(visible.count))") {
        ForEach(visible) { record in
          flagRow(record)
        }
      }
    }
    .navigationTitle("FlagFlipper")
    .searchable(text: $search, prompt: "Flag or domain")
    .toolbar {
      Button("Refresh", systemImage: "arrow.clockwise") { store.refresh() }
    }
    .onAppear { store.refresh() }
    .onChange(of: access.isReady) { _, ready in if ready { store.refresh() } }
  }

  @ViewBuilder
  private func flagRow(_ record: FlagRecord) -> some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(record.key.name).font(.body).textSelection(.enabled)
        Text(record.key.domain)
          .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        Text("\(record.override.label) · Definition: \(record.defaultLabel)")
          .font(.caption2).foregroundStyle(.secondary)
        if let phase = record.developmentPhase {
          Text("Phase: \(phase)").font(.caption2).foregroundStyle(.tertiary)
        }
      }
      Spacer(minLength: 0)
      Menu {
        Button("Force On", systemImage: "checkmark.circle") {
          store.set(record.key, enabled: true)
        }
        Button("Force Off", systemImage: "xmark.circle") {
          store.set(record.key, enabled: false)
        }
        Button("Use Default", systemImage: "arrow.uturn.backward") {
          store.set(record.key, enabled: nil)
        }
      } label: {
        Image(systemName: record.override == .on ? "checkmark.circle.fill"
          : record.override == .off ? "xmark.circle.fill" : "ellipsis.circle")
          .font(.title3)
          .accessibilityLabel("Change \(record.key.domain) / \(record.key.name)")
      }
      .disabled(!access.isReady || store.isBusy || store.needsOwnershipRepair)
    }
    .padding(.vertical, 3)
  }
}
