import Foundation
import SwiftData

/// Пользовательский плейлист (вкладка на главном экране).
@Model
final class Playlist {
    @Attribute(.unique) var uid: UUID
    var name: String
    /// Позиция вкладки среди плейлистов.
    var orderIndex: Int
    /// "alphabetical" или "custom" (см. ListSortMode).
    var sortModeRaw: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
    var entries: [PlaylistEntry] = []

    init(name: String, orderIndex: Int) {
        self.uid = UUID()
        self.name = name
        self.orderIndex = orderIndex
        self.sortModeRaw = ListSortMode.custom.rawValue
        self.createdAt = Date()
    }

    var sortMode: ListSortMode {
        get { ListSortMode(rawValue: sortModeRaw) ?? .custom }
        set { sortModeRaw = newValue.rawValue }
    }
}

/// Строка плейлиста: связь «плейлист — трек» с явным порядком.
/// Порядок хранится числом, потому что SwiftData не гарантирует порядок связей.
@Model
final class PlaylistEntry {
    @Attribute(.unique) var uid: UUID
    var orderIndex: Int
    var addedAt: Date
    var playlist: Playlist?
    var track: TrackRecord?

    init(orderIndex: Int) {
        self.uid = UUID()
        self.orderIndex = orderIndex
        self.addedAt = Date()
    }
}

/// Режим порядка в списке.
enum ListSortMode: String, Codable, Sendable {
    /// По имени файла, с естественной сортировкой чисел.
    case alphabetical
    /// Ручной порядок (после перетаскивания или «Перемешать список»).
    case custom
}
