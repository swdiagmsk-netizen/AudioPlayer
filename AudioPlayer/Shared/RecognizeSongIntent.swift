import AppIntents
import Foundation

/// Действие «Распознать песню». Его вызывает кнопка на экране блокировки
/// (расширение PlayMyDiskWidget). Файл входит и в приложение, и в расширение.
struct RecognizeSongIntent: AppIntent {
    static var title: LocalizedStringResource { "Распознать песню" }
    static var description: IntentDescription { IntentDescription("Открывает PlayMyDisk и запускает распознавание песни.") }

    // VERIFY: с openAppWhenRun действие выполняется в процессе приложения — проверить на телефоне.
    static var openAppWhenRun: Bool { true }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        RecognitionRequest.post()
        return .result()
    }
}

/// Запрос на распознавание из кнопки экрана блокировки.
/// Сохраняется в настройках, чтобы его подхватило и только что запущенное приложение.
enum RecognitionRequest {
    static let notification = Notification.Name("PlayMyDisk.recognitionRequest")
    private static let key = "recognition.requestedAt"
    /// Запрос старше этого времени считается устаревшим.
    private static let lifetime: TimeInterval = 30

    @MainActor
    static func post() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// true — есть свежий запрос (и он снимается).
    @MainActor
    static func consume() -> Bool {
        let defaults = UserDefaults.standard
        let requestedAt = defaults.double(forKey: key)
        guard requestedAt > 0 else { return false }
        defaults.removeObject(forKey: key)
        return Date().timeIntervalSince1970 - requestedAt <= lifetime
    }
}
