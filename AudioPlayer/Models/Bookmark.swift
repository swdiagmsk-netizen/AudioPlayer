import Foundation
import SwiftData

/// Закладка внутри трека: секунда + заметка.
@Model
final class Bookmark {
    @Attribute(.unique) var uid: UUID
    /// Позиция в секундах от начала файла.
    var time: Double
    var note: String
    var createdAt: Date
    var track: TrackRecord?

    init(time: Double, note: String) {
        self.uid = UUID()
        self.time = time
        self.note = note
        self.createdAt = Date()
    }
}

/// Состояние списка, у которого нет своей модели:
/// вкладка «Все треки» (ключ "all") и папки (ключ "folder:<путь>").
@Model
final class ListState {
    @Attribute(.unique) var key: String
    /// "alphabetical" или "custom".
    var sortModeRaw: String
    /// Папка помечена как «Аудиокниги».
    var isAudiobookFolder: Bool

    init(key: String) {
        self.key = key
        self.sortModeRaw = ListSortMode.alphabetical.rawValue
        self.isAudiobookFolder = false
    }

    var sortMode: ListSortMode {
        get { ListSortMode(rawValue: sortModeRaw) ?? .alphabetical }
        set { sortModeRaw = newValue.rawValue }
    }
}
