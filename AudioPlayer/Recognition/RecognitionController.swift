import AVFoundation
import Observation
import UIKit

/// Кнопка «Распознать»: пауза → распознавание → результат → продолжение с той же секунды.
@MainActor
@Observable
final class RecognitionController {
    enum Phase: Equatable {
        case idle
        case listening
        case found(RecognizedSong)
        case notFound
        case micDenied
        /// ShazamKit недоступен; `openedShazam` — удалось ли открыть приложение Shazam.
        case unavailable(openedShazam: Bool)
    }

    private(set) var phase: Phase = .idle

    var isPresented: Bool { phase != .idle }

    private let playback: PlaybackController
    /// Играла ли музыка до нажатия — тогда после закрытия продолжаем.
    @ObservationIgnored private var resumeAfter = false
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Сколько ждать результата.
    private let timeout: Duration = .seconds(15)

    init(playback: PlaybackController) {
        self.playback = playback
    }

    /// Нажатие кнопки «Распознать».
    func start() {
        guard phase == .idle else { return }
        resumeAfter = playback.isPlaying
        if resumeAfter {
            playback.pause()
        }
        listen()
    }

    /// «Ещё раз» на экране результата.
    func retry() {
        task?.cancel()
        listen()
    }

    /// Закрытие экрана результата (кнопкой или свайпом).
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

    private func listen() {
        phase = .listening
        task = Task { [weak self] in
            guard let self else { return }
            guard await Self.microphoneAllowed() else {
                AppLogger.shared.log("shazam", "Нет доступа к микрофону")
                if !Task.isCancelled { phase = .micDenied }
                return
            }
            prepareRecordingSession()
            let outcome = await MusicRecognizer.recognize(timeout: timeout)
            guard !Task.isCancelled, phase == .listening else { return }
            playback.restoreAudioSession()
            switch outcome {
            case .match(let song):
                AppLogger.shared.log("shazam", "Распознано: \(song.artist) — \(song.title)")
                Haptics.select()
                phase = .found(song)
            case .noMatch:
                AppLogger.shared.log("shazam", "Песня не найдена")
                phase = .notFound
            case .failed(let reason):
                AppLogger.shared.log("shazam", "Ошибка ShazamKit: \(reason)")
                let opened = await openShazamApp()
                guard !Task.isCancelled, phase == .listening else { return }
                phase = .unavailable(openedShazam: opened)
            }
        }
    }

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
