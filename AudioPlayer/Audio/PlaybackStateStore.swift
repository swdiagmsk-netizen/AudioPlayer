import Foundation

/// Что сохраняется при закрытии, чтобы продолжить с того же места.
struct SavedPlaybackState: Codable, Sendable {
    /// Очередь с режимами повтора и рандома.
    var queue: PlaybackQueue
    /// Позиция в секундах.
    var position: Double
    /// Скорость воспроизведения.
    var rate: Float
    /// Играла ли музыка в момент сохранения.
    var wasPlaying: Bool
    /// Ключ открытого списка (вкладка, плейлист, папка).
    var contextKey: String?
}

/// Хранение состояния воспроизведения в UserDefaults (JSON).
enum PlaybackStateStore {
    private static let key = "playback.savedState.v2"

    static func save(_ state: SavedPlaybackState) {
        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            AppLogger.shared.log("state", "Не удалось сохранить состояние: \(error.localizedDescription)")
        }
    }

    static func load() -> SavedPlaybackState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedPlaybackState.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
