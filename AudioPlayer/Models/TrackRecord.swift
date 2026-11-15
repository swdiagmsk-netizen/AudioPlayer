import Foundation
import SwiftData

/// Запись о треке в библиотеке. Живёт в SwiftData.
/// `uid` — стабильный идентификатор: он не меняется при переименовании и
/// перемещении файла, к нему привязаны закладки, плейлисты и счётчики.
@Model
final class TrackRecord {
    @Attribute(.unique) var uid: UUID

    // Файл
    /// Путь относительно папки Documents, например "Rock/song.mp3".
    var relativePath: String
    var fileName: String
    /// Отпечаток содержимого: размер + SHA-256 первого мегабайта.
    var fingerprint: String
    var fileSize: Int64
    var dateAdded: Date

    // Теги
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var genre: String
    var year: String
    var trackNumber: String
    var composer: String
    var comment: String
    var hasArtwork: Bool

    // Технические сведения
    var duration: Double
    var formatName: String
    var bitrateKbps: Int
    var sampleRate: Double
    /// Файл защищён DRM (.m4p, .aa, .aax) — воспроизвести нельзя.
    var isProtected: Bool
    /// Файл удалось открыть как аудио.
    var isPlayable: Bool

    // Статистика и отметки
    var playCount: Int
    var lastPlayedAt: Date?
    /// Отметка «Супер!» (сердечко).
    var isSuper: Bool
    var superAt: Date?

    // Аудиокниги
    var lastPosition: Double
    var isFinished: Bool

    // Громкость (заполняется анализом на этапе нормализации)
    var loudnessLUFS: Double?

    // Порядок в списках
    /// Позиция во вкладке «Все треки» при ручном порядке.
    var allOrderIndex: Int
    /// Позиция внутри своей папки при ручном порядке.
    var folderOrderIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.track)
    var bookmarks: [Bookmark] = []

    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.track)
    var entries: [PlaylistEntry] = []

    init(relativePath: String, fileName: String, fingerprint: String, fileSize: Int64) {
        self.uid = UUID()
        self.relativePath = relativePath
        self.fileName = fileName
        self.fingerprint = fingerprint
        self.fileSize = fileSize
        self.dateAdded = Date()
        self.title = ""
        self.artist = ""
        self.album = ""
        self.albumArtist = ""
        self.genre = ""
        self.year = ""
        self.trackNumber = ""
        self.composer = ""
        self.comment = ""
        self.hasArtwork = false
        self.duration = 0
        self.formatName = ""
        self.bitrateKbps = 0
        self.sampleRate = 0
        self.isProtected = false
        self.isPlayable = true
        self.playCount = 0
        self.lastPlayedAt = nil
        self.isSuper = false
        self.superAt = nil
        self.lastPosition = 0
        self.isFinished = false
        self.loudnessLUFS = nil
        self.allOrderIndex = 0
        self.folderOrderIndex = 0
    }

    /// Полный путь к файлу на устройстве.
    var fileURL: URL {
        LibraryPaths.url(forRelative: relativePath)
    }

    /// Папка трека относительно Documents ("" — корень).
    var folderPath: String {
        LibraryPaths.parentFolder(ofRelative: relativePath)
    }

    /// Название для показа: тег, а если его нет — имя файла без расширения.
    var displayTitle: String {
        if !title.isEmpty { return title }
        return (fileName as NSString).deletingPathExtension
    }

    /// Исполнитель для показа (пустая строка, если тег не задан — подпись подставляет интерфейс).
    var displayArtist: String {
        artist
    }
}
