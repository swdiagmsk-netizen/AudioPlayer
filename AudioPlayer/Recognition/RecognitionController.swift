import AVFoundation
import Observation
import UIKit

/// Кнопка «Распознать»: пауза → слушаем до результата (не дольше минуты) → результат →
/// продолжение с той же секунды. Без связи или без результата фрагмент уходит в буфер
/// и распознаётся автоматически при стабильной сети.
@MainActor
@Observable
final class RecognitionController {
    enum Phase: Equatable {
        case idle
        case listening(since: Date)
        case found(RecognizedSong)
        /// Не нашли за минуту. `saved` — фрагмент сохранён для повтора.
        case notFound(saved: Bool)
        /// Нет связи; фрагмент сохранён (или нет, если записать не удалось).
        case offline(saved: Bool)
        case micDenied
        /// ShazamKit недоступен; `openedShazam` — удалось ли открыть приложение Shazam.
        case unavailable(openedShazam: Bool)
    }

    private(set) var phase: Phase = .idle
    /// Песни, найденные по отложенным фрагментам, — показываем по одной.
    private(set) var announcements: [RecognizedSong] = []

    let store = RecognitionStore()

    var isPresented: Bool { phase != .idle }

    /// Сколько слушать, если песня не находится.
    static let maxListen: Duration = .seconds(60)

    private let playback: PlaybackController
    @ObservationIgnored private let network = NetworkMonitor()
    @ObservationIgnored private var resumeAfter = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var isProcessingPending = false

    init(playback: PlaybackController) {
        self.playback = playback
        network.start { [weak self] online in
            Task { @MainActor [weak self] in
                self?.networkChanged(online: online)
            }
        }
    }

    // MARK: - Распознавание по кнопке

    func start() {
        guard phase == .idle else { return }
        resumeAfter = playback.isPlaying
        if resumeAfter {
            playback.pause()
        }
        listen()
    }

    func retry() {
        task?.cancel()
        listen()
    }

    /// Закрытие экрана (кнопкой или свайпом) — музыка продолжает играть, если играла.
    func close() {
        task?.cancel()
        task = nil
        guard phase != .idle else { return }
        phase = .idle
        if resumeAfter {
            resumeAfter = false
            playback.play()
        } else {
            playback.restoreAudioSession()
        }
    }

    /// Включить музыку после закрытия экрана (при запуске приложения кнопкой «Распознать»).
    func resumeWhenClosed() {
        guard phase != .idle else { return }
        resumeAfter = true
    }

    func dismissAnnouncement() {
        if !announcements.isEmpty {
            announcements.removeFirst()
        }
    }

    private func listen() {
        phase = .listening(since: .now)
        task = Task { [weak self] in
            guard let self else { return }
            guard await Self.microphoneAllowed() else {
                AppLogger.shared.log("shazam", "Нет доступа к микрофону")
                if !Task.isCancelled { phase = .micDenied }
                return
            }
            prepareRecordingSession()
            let outcome = await MusicRecognizer.listen(maxDuration: Self.maxListen, network: network)
            guard !Task.isCancelled, case .listening = phase else { return }
            playback.restoreAudioSession()
            switch outcome {
            case .match(let song):
                AppLogger.shared.log("shazam", "Распознано: \(song.displayLine)")
                Haptics.select()
                store.addFound(song)
                phase = .found(song)
            case .noMatch(let signature):
                let saved = signature.map { store.addPending(signature: $0) } ?? false
                AppLogger.shared.log("shazam", "Не найдено за минуту; фрагмент в буфере: \(saved)")
                phase = .notFound(saved: saved)
            case .offline(let signature):
                let saved = signature.map { store.addPending(signature: $0) } ?? false
                AppLogger.shared.log("shazam", "Нет связи; фрагмент в буфере: \(saved)")
                phase = .offline(saved: saved)
            case .failed(let reason):
                AppLogger.shared.log("shazam", "Ошибка ShazamKit: \(reason)")
                let opened = await openShazamApp()
                guard !Task.isCancelled, case .listening = phase else { return }
                phase = .unavailable(openedShazam: opened)
            }
        }
    }

    // MARK: - Отложенные фрагменты

    /// Сеть появилась — ждём, что она стабильна (5 с), и пробуем отложенные фрагменты.
    private func networkChanged(online: Bool) {
        retryTask?.cancel()
        guard online, !store.pending.isEmpty else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.network.isOnline else { return }
            await self.processPending()
        }
    }

    /// Приложение снова на экране — если есть сеть, пробуем отложенные.
    func processPendingIfOnline() {
        guard network.isOnline, !store.pending.isEmpty else { return }
        Task { await processPending() }
    }

    /// Кнопка «Повторить сейчас» в истории.
    func processPending() async {
        guard !isProcessingPending else { return }
        isProcessingPending = true
        defer { isProcessingPending = false }
        for entry in store.pending {
            guard network.isOnline else { break }
            guard let data = store.signatureData(for: entry) else {
                store.markAttemptFailed(entry.id)
                continue
            }
            let outcome = await MusicRecognizer.match(signatureData: data, network: network)
            switch outcome {
            case .match(let song):
                AppLogger.shared.log("shazam", "Отложенный фрагмент распознан: \(song.displayLine)")
                store.markFound(entry.id, song: song)
                announcements.append(song)
            case .noMatch:
                store.markAttemptFailed(entry.id)
            case .offline:
                return
            case .failed(let reason):
                AppLogger.shared.log("shazam", "Отложенный фрагмент: ошибка \(reason)")
                store.markAttemptFailed(entry.id)
            }
        }
    }

    // MARK: - Вспомогательное

    /// Запасной вариант: приложение Shazam, если установлено.
    private func openShazamApp() async -> Bool {
        // VERIFY: URL-схема приложения Shazam официально не документирована.
        guard let url = URL(string: "shazam://") else { return false }
        let opened = await UIApplication.shared.open(url)
        AppLogger.shared.log("shazam", opened ? "Открыто приложение Shazam" : "Приложение Shazam не установлено")
        return opened
    }

    /// Для записи с микрофона нужна категория «воспроизведение и запись».
    /// Музыка в этот момент на паузе; после распознавания категория возвращается обратно.
    private func prepareRecordingSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            AppLogger.shared.log("shazam", "Не удалось включить запись: \(error.localizedDescription)")
        }
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        default:
            return await AVAudioApplication.requestRecordPermission()
        }
    }
}
