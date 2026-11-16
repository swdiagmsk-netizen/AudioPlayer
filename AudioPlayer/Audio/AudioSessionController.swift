import AVFoundation

/// Аудиосессия: категория .playback (звук на заблокированном экране и в фоне),
/// прерывания (звонки, будильник), отключение наушников, сброс медиасервисов.
@MainActor
final class AudioSessionController {
    /// Началось прерывание (звонок и т.п.) — нужно встать на паузу.
    var onInterruptionBegan: (() -> Void)?
    /// Прерывание закончилось; true — iOS разрешает продолжить.
    var onInterruptionEnded: ((Bool) -> Void)?
    /// Отключили наушники или Bluetooth — пауза.
    var onOldDeviceUnavailable: (() -> Void)?
    /// iOS сбросила медиасервисы — граф нужно пересоздать.
    var onMediaServicesReset: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    /// Включает сессию. `spokenAudio` — режим для аудиокниг и подкастов.
    func activate(spokenAudio: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: spokenAudio ? .spokenAudio : .default)
            try session.setActive(true)
        } catch {
            AppLogger.shared.log("session", "Не удалось активировать аудиосессию: \(error.localizedDescription)")
        }
    }

    func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        // Колбэки приходят на главную очередь (queue: .main), поэтому
        // MainActor.assumeIsolated здесь безопасен.
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleRouteChange(reasonRaw: reasonRaw)
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                AppLogger.shared.log("session", "Медиасервисы iOS были сброшены")
                self?.onMediaServicesReset?()
            }
        })
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            AppLogger.shared.log("session", "Прерывание началось")
            onInterruptionBegan?()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            let shouldResume = options.contains(.shouldResume)
            AppLogger.shared.log("session", "Прерывание закончилось, продолжать: \(shouldResume)")
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonRaw: UInt?) {
        guard let reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        if reason == .oldDeviceUnavailable {
            AppLogger.shared.log("session", "Аудиоустройство отключено — пауза")
            onOldDeviceUnavailable?()
        }
    }
}
