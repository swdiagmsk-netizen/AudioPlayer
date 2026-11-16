import Foundation
import ShazamKit

/// Распознанная песня. Только простые значения — их безопасно передавать между потоками.
struct RecognizedSong: Sendable, Equatable {
    let title: String
    let artist: String
    let artworkURL: URL?
    let appleMusicURL: URL?
    let webURL: URL?
}

/// Итог одной попытки распознавания.
enum RecognitionOutcome: Sendable, Equatable {
    case match(RecognizedSong)
    /// Песня не найдена или вышло время ожидания.
    case noMatch
    /// ShazamKit не сработал (например, нет услуги ShazamKit при бесплатной подписи).
    case failed(String)
}

/// Распознавание по микрофону через ShazamKit (`SHManagedSession` сам пишет звук с микрофона).
/// Всё, что связано со ShazamKit, живёт внутри одной функции и не пересекает границы акторов.
enum MusicRecognizer {
    nonisolated static func recognize(timeout: Duration) async -> RecognitionOutcome {
        let session = SHManagedSession()
        // Ссылка для остановки по таймауту. Метод cancel() предназначен для вызова
        // во время ожидания результата, поэтому снимаем проверку Sendable.
        nonisolated(unsafe) let cancellable = session
        let clock = ContinuousClock()
        let started = clock.now

        let timer = Task.detached {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled {
                cancellable.cancel()
            }
        }
        defer { timer.cancel() }

        // VERIFY: при подписи бесплатным Apple ID услуга ShazamKit у App ID, скорее всего,
        // недоступна — тогда здесь придёт .error, и сработает запасной вариант.
        // Отмена задачи (кнопка «Отмена», «Ещё раз») сразу останавливает запись с микрофона
        let result = await withTaskCancellationHandler {
            await session.result()
        } onCancel: {
            cancellable.cancel()
        }
        switch result {
        case .match(let match):
            guard let item = match.mediaItems.first else { return .noMatch }
            return .match(RecognizedSong(
                title: item.title ?? "Без названия",
                artist: item.artist ?? "",
                artworkURL: item.artworkURL,
                appleMusicURL: item.appleMusicURL,
                webURL: item.webURL
            ))
        case .noMatch:
            return .noMatch
        case .error(let error, _):
            // Остановка по таймауту тоже приходит ошибкой — это «не нашли», а не сбой
            if started.duration(to: clock.now) >= timeout - .milliseconds(500) {
                return .noMatch
            }
            let nsError = error as NSError
            return .failed("\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
        @unknown default:
            return .noMatch
        }
    }
}
