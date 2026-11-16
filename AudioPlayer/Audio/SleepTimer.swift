import Foundation
import Observation

/// Таймер сна: через заданное время (или в конце трека) плавно убавляет
/// громкость и ставит на паузу. Работает в фоне, пока играет музыка.
@MainActor
@Observable
final class SleepTimer {
    enum Mode: Equatable {
        case off
        /// Пауза в заданный момент.
        case until(Date)
        /// Пауза в конце текущего трека.
        case endOfTrack
    }

    private(set) var mode: Mode = .off
    /// Сколько осталось до паузы (для режима .until), секунды.
    private(set) var remaining: TimeInterval = 0

    /// Время вышло — нужно поставить на паузу.
    @ObservationIgnored var onFire: (() -> Void)?
    @ObservationIgnored private var loop: Task<Void, Never>?

    var isActive: Bool { mode != .off }

    /// Запуск на N минут (1 минута — 12 часов).
    func start(minutes: Int) {
        let clamped = min(max(minutes, 1), 720)
        mode = .until(Date().addingTimeInterval(TimeInterval(clamped * 60)))
        AppLogger.shared.log("sleep", "Таймер сна: \(clamped) мин")
        runLoop()
    }

    func startEndOfTrack() {
        mode = .endOfTrack
        remaining = 0
        loop?.cancel()
        AppLogger.shared.log("sleep", "Таймер сна: до конца трека")
    }

    /// +5 минут к работающему таймеру.
    func extend(minutes: Int = 5) {
        guard case .until(let date) = mode else { return }
        mode = .until(date.addingTimeInterval(TimeInterval(minutes * 60)))
        updateRemaining()
    }

    func cancel() {
        mode = .off
        remaining = 0
        loop?.cancel()
        loop = nil
    }

    /// Множитель громкости 0…1 для затухания в последние N секунд (режим .until).
    func fadeFactor() -> Float {
        guard case .until = mode else { return 1 }
        let fade = Double(AppSettings.sleepFadeSeconds)
        guard fade > 0, remaining < fade else { return 1 }
        return Float(max(0, remaining / fade))
    }

    /// Вызывается, когда трек доиграл. true — таймер сработал (дальше не играть).
    func trackDidFinish() -> Bool {
        guard mode == .endOfTrack else { return false }
        cancel()
        return true
    }

    private func updateRemaining() {
        if case .until(let date) = mode {
            remaining = max(0, date.timeIntervalSinceNow)
        }
    }

    private func runLoop() {
        loop?.cancel()
        updateRemaining()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.updateRemaining()
                if case .until = self.mode, self.remaining <= 0 {
                    self.mode = .off
                    self.loop = nil
                    AppLogger.shared.log("sleep", "Таймер сна сработал")
                    self.onFire?()
                    return
                }
            }
        }
    }
}
