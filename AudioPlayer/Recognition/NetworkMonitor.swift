import Foundation
import Network

/// Следит за связью (сотовая сеть или Wi-Fi). Потокобезопасен.
final class NetworkMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "playmydisk.network")
    private let lock = NSLock()
    private var online = false
    private var started = false

    /// Есть ли сейчас связь с интернетом.
    var isOnline: Bool {
        lock.withLock { online }
    }

    /// Запуск наблюдения. `onChange` вызывается на фоновой очереди при каждом изменении.
    func start(onChange: @escaping @Sendable (Bool) -> Void) {
        let alreadyStarted = lock.withLock {
            defer { started = true }
            return started
        }
        guard !alreadyStarted else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isOnline = path.status == .satisfied
            let changed = self.lock.withLock {
                defer { self.online = isOnline }
                return self.online != isOnline
            }
            if changed {
                onChange(isOnline)
            }
        }
        monitor.start(queue: queue)
    }
}
