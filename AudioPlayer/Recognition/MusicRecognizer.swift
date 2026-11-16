import Foundation
import ShazamKit

/// Распознанная песня. Только простые значения — их безопасно передавать между потоками и хранить.
struct RecognizedSong: Sendable, Equatable, Codable {
    let title: String
    let artist: String
    let artworkURL: URL?
    let webURL: URL?

    /// Формат показа и копирования: «Исполнитель - Название».
    var displayLine: String {
        artist.isEmpty ? title : "\(artist) - \(title)"
    }
}

/// Итог прослушивания с микрофона.
enum LiveRecognitionOutcome: Sendable {
    case match(RecognizedSong)
    /// За отведённое время не нашли. `signature` — записанный фрагмент для повтора позже.
    case noMatch(signature: Data?)
    /// Нет связи. `signature` — записанный фрагмент для распознавания, когда появится сеть.
    case offline(signature: Data?)
    /// ShazamKit не сработал (например, нет услуги ShazamKit при бесплатной подписи).
    case failed(String)
}

/// Итог повторной попытки по сохранённому фрагменту.
enum DeferredRecognitionOutcome: Sendable {
    case match(RecognizedSong)
    case noMatch
    case offline
    case failed(String)
}

/// Распознавание через ShazamKit. Всё, что связано со ShazamKit, живёт внутри этих функций
/// и не пересекает границы акторов — наружу выходят только простые значения.
enum MusicRecognizer {
    /// Сколько записывать без связи, прежде чем сохранить фрагмент в буфер.
    nonisolated static let offlineCapture: Duration = .seconds(12)

    /// Слушает микрофон, пока не найдёт песню, но не дольше `maxDuration`.
    nonisolated static func listen(maxDuration: Duration, network: NetworkMonitor) async -> LiveRecognitionOutcome {
        let session = SHManagedSession()
        let clock = ContinuousClock()
        let started = clock.now
        var best: SHSignature?

        func keep(_ signature: SHSignature) {
            if let current = best, current.duration >= signature.duration { return }
            best = signature
        }

        // Останавливаем запись по истечении времени
        let timer = Task.detached {
            try? await Task.sleep(for: maxDuration)
            if !Task.isCancelled {
                session.cancel()
            }
        }
        defer { timer.cancel() }

        // VERIFY: поведение SHManagedSession без сети (как быстро приходит ошибка и какой длины
        // фрагмент в ней) проверить на телефоне. Берём самый длинный из полученных фрагментов.
        let outcome: LiveRecognitionOutcome? = await withTaskCancellationHandler {
            for await result in session.results {
                let elapsed = started.duration(to: clock.now)
                switch result {
                case .match(let match):
                    if let item = match.mediaItems.first {
                        return .match(RecognizedSong(
                            title: item.title ?? "Без названия",
                            artist: item.artist ?? "",
                            artworkURL: item.artworkURL,
                            webURL: item.webURL
                        ))
                    }
                case .noMatch(let signature):
                    keep(signature)
                case .error(let error, let signature):
                    keep(signature)
                    if Task.isCancelled || elapsed >= maxDuration - .milliseconds(500) {
                        return nil
                    }
                    if !network.isOnline || isNetworkError(error) {
                        if elapsed >= offlineCapture {
                            return .offline(signature: best?.dataRepresentation)
                        }
                        // Без сети ошибки могут идти подряд — даём микрофону дописать звук
                        try? await Task.sleep(for: .milliseconds(300))
                    } else {
                        let nsError = error as NSError
                        return .failed("\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
                    }
                @unknown default:
                    break
                }
                if started.duration(to: clock.now) >= maxDuration - .milliseconds(500) {
                    return nil
                }
            }
            return nil
        } onCancel: {
            session.cancel()
        }
        session.cancel()

        if let outcome { return outcome }
        if !network.isOnline {
            return .offline(signature: best?.dataRepresentation)
        }
        return .noMatch(signature: best?.dataRepresentation)
    }

    /// Повторное распознавание по сохранённому фрагменту (без микрофона).
    nonisolated static func match(signatureData: Data, network: NetworkMonitor) async -> DeferredRecognitionOutcome {
        let signature: SHSignature
        do {
            signature = try SHSignature(dataRepresentation: signatureData)
        } catch {
            return .failed("Фрагмент повреждён: \(error.localizedDescription)")
        }
        let session = SHSession()
        let result = await session.result(from: signature)
        switch result {
        case .match(let match):
            guard let item = match.mediaItems.first else { return .noMatch }
            return .match(RecognizedSong(
                title: item.title ?? "Без названия",
                artist: item.artist ?? "",
                artworkURL: item.artworkURL,
                webURL: item.webURL
            ))
        case .noMatch:
            return .noMatch
        case .error(let error, _):
            if !network.isOnline || isNetworkError(error) {
                return .offline
            }
            let nsError = error as NSError
            return .failed("\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
        @unknown default:
            return .noMatch
        }
    }

    /// Ошибка связи — сама или как вложенная причина.
    nonisolated private static func isNetworkError(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == NSURLErrorDomain { return true }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
