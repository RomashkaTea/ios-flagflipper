import Combine
import Darwin
import Foundation

@MainActor
final class AccessController: ObservableObject {
  static let shared = AccessController()

  @Published private(set) var isWorking = false
  @Published private(set) var isReady = false
  @Published private(set) var progress = 0.0
  @Published private(set) var message = "Access has not been prepared."

  private init() {}

  private static var isDebugged: Bool {
    var info = kinfo_proc()
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var size = MemoryLayout<kinfo_proc>.stride
    return sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0
      && (info.kp_proc.p_flag & 0x800) != 0
  }

  func prepare() {
    guard !isWorking, !isReady else { return }
    guard DeviceGate.isSupported else {
      message = DeviceGate.unsupportedReason ?? "This device is not supported."
      return
    }
    guard !Self.isDebugged else {
      message = "Close the debugger before preparing access."
      return
    }
    isWorking = true
    progress = 0
    message = "Preparing file access…"
    init_offsets()
    offsets_init()
    ds_set_progress_callback { value in
      DispatchQueue.main.async { AccessController.shared.progress = value }
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let kernelReady = ds_run() == 0 && ds_is_ready()
      guard kernelReady else {
        DispatchQueue.main.async {
          AccessController.shared.message = "Access failed; no flags changed."
          AccessController.shared.isWorking = false
        }
        return
      }
      let offsetsReady =
        emergencyfixfunctiontobereplacedlateronquestionmark()
        || (KernelcacheLoader.fetch() && dlkcache())
      guard offsetsReady else {
        DispatchQueue.main.async {
          AccessController.shared.message = "Could not load offsets; no flags changed."
          AccessController.shared.isWorking = false
        }
        return
      }
      let sandboxReady = sbx_escape(ds_get_our_proc()) == 0
      DispatchQueue.main.async {
        AccessController.shared.isReady = sandboxReady
        AccessController.shared.message = sandboxReady
          ? "Access ready. Select a flag to force on, force off, or use its default."
          : "File access failed; no flags changed."
        AccessController.shared.isWorking = false
      }
    }
  }
}
