import Foundation
import SwiftData
import Observation

/// Какой список открыт на главном экране.
enum ListID: Hashable, Sendable {
    /// ★ Твой хит-парад.
    case hitParade
    /// ♥ Супер!
    case superList
    /// Все треки.
    case all
    /// Папка (путь относительно Documents, "" — корень).
    case folder(String)
    /// Пользовательский плейлист.
    case playlist(UUID)

    /// Строковый ключ для сохранения.
    var key: String {
        switch self {
        case .hitParade: return "hit"
        case .superList: return "super"
        case .all: return "all"
        case .folder(let path): return "folder:" + path
        case .playlist(let uid): return "playlist:" + uid.uuidString
        }
    }

    init?(key: String) {
        if key == "hit" { self = .hitParade; return }
        if key == "super" { self = .superList; return }
        if key == "all" { self = .all; return }
        if key.hasPrefix("folder:") {
            self = .folder(String(key.dropFirst("folder:".count)))
            return
        }
        if key.hasPrefix("playlist:"), let uid = UUID(uuidString: String(key.dropFirst("playlist:".count))) {
            self = .playlist(uid)
            return
        }
        return nil
    }

    /// Порядок в списке можно менять вручную (у ★ и ♥ он автоматический).
    var isReorderable: Bool {
        switch self {
        case .hitParade, .superList: return false
        default: return true
        }
    }
}

/// Списки и плейлисты: порядок показа, «Перемешать список», «А–Я»,
/// перетаскивание, ★ хит-парад, ♥ «Супер!».
@MainActor
@Observable
final class QueueAndPlaylistManager {
    /// Пользовательские плейлисты в порядке вкладок.
    private(set) var playlists: [Playlist] = []
    /// Увеличивается при любом изменении порядка — интерфейс перечитывает списки.
    private(set) var revision: Int = 0

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let library: LibraryAndBookmarkManager

    init(context: ModelContext, library: LibraryAndBookmarkManager) {
        self.context = context
        self.library = library
        reloadPlaylists()
    }

    // MARK: - Содержимое списков

    /// Треки списка в порядке показа.
    func tracks(for list: ListID) -> [TrackRecord] {
        // Чтение revision подписывает интерфейс на изменения порядка
        _ = revision
        switch list {
        case .hitParade:
            return library.tracks
                .filter { $0.playCount > 0 }
                .sorted { a, b in
                    if a.playCount != b.playCount { return a.playCount > b.playCount }
                    return (a.lastPlayedAt ?? .distantPast) > (b.lastPlayedAt ?? .distantPast)
                }
        case .superList:
            return library.tracks
                .filter { $0.isSuper }
                .sorted { ($0.superAt ?? .distantPast) > ($1.superAt ?? .distantPast) }
        case .all:
            // library.tracks уже отсортированы по имени файла
            if sortMode(for: list) == .custom {
                return library.tracks.sorted { $0.allOrderIndex < $1.allOrderIndex }
            }
            return library.tracks
        case .folder(let path):
            let inFolder = library.tracksInFolder(path)
            if sortMode(for: list) == .custom {
                return inFolder.sorted { $0.folderOrderIndex < $1.folderOrderIndex }
            }
            return inFolder
        case .playlist:
            return entries(for: list).compactMap { $0.track }
        }
    }

    /// Строки плейлиста в порядке показа (для остальных списков — пусто).
    func entries(for list: ListID) -> [PlaylistEntry] {
        guard case .playlist(let uid) = list, let found = playlist(withUID: uid) else { return [] }
        let valid = found.entries.filter { $0.track != nil }
        if found.sortMode == .custom {
            return valid.sorted { $0.orderIndex < $1.orderIndex }
        }
        return valid.sorted { a, b in
            let nameA = a.track?.fileName ?? ""
            let nameB = b.track?.fileName ?? ""
            let order = nameA.localizedStandardCompare(nameB)
            if order != .orderedSame { return order == .orderedAscending }
            return a.orderIndex < b.orderIndex
        }
    }

    func playlist(withUID uid: UUID) -> Playlist? {
        playlists.first { $0.uid == uid }
    }

    // MARK: - Порядок

    func sortMode(for list: ListID) -> ListSortMode {
        switch list {
        case .hitParade, .superList:
            return .custom
        case .playlist(let uid):
            return playlist(withUID: uid)?.sortMode ?? .custom
        case .all, .folder:
            return listState(for: list.key, create: false)?.sortMode ?? .alphabetical
        }
    }

    /// Кнопка «А–Я»: сортировка по имени файла с естественным порядком чисел.
    func sortAlphabetically(_ list: ListID) {
        setSortMode(.alphabetical, for: list)
        commit("sortAZ")
    }

    /// Кнопка «Перемешать список»: физически меняет порядок показа (Фишер — Йейтс).
    func shuffleList(_ list: ListID) {
        guard list.isReorderable else { return }
        if case .playlist = list {
            let shuffled = FisherYates.shuffled(entries(for: list))
            writeOrder(entries: shuffled)
        } else {
            let shuffled = FisherYates.shuffled(tracks(for: list))
            writeOrder(tracks: shuffled, for: list)
        }
        setSortMode(.custom, for: list)
        commit("shuffleList")
    }

    /// Перетаскивание строк в списке.
    func move(in list: ListID, fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard list.isReorderable else { return }
        if case .playlist = list {
            let reordered = FisherYates.moved(entries(for: list), fromOffsets: offsets, toOffset: destination)
            writeOrder(entries: reordered)
        } else {
            let reordered = FisherYates.moved(tracks(for: list), fromOffsets: offsets, toOffset: destination)
            writeOrder(tracks: reordered, for: list)
        }
        setSortMode(.custom, for: list)
        commit("move")
    }

    private func writeOrder(tracks: [TrackRecord], for list: ListID) {
        for (index, track) in tracks.enumerated() {
            if case .folder = list {
                track.folderOrderIndex = index
            } else {
                track.allOrderIndex = index
            }
        }
    }

    private func writeOrder(entries: [PlaylistEntry]) {
        for (index, entry) in entries.enumerated() {
            entry.orderIndex = index
        }
    }

    private func setSortMode(_ mode: ListSortMode, for list: ListID) {
        switch list {
        case .hitParade, .superList:
            break
        case .playlist(let uid):
            playlist(withUID: uid)?.sortMode = mode
        case .all, .folder:
            listState(for: list.key, create: true)?.sortMode = mode
        }
    }

    private func listState(for key: String, create: Bool) -> ListState? {
        let all = (try? context.fetch(FetchDescriptor<ListState>())) ?? []
        if let found = all.first(where: { $0.key == key }) {
            return found
        }
        guard create else { return nil }
        let state = ListState(key: key)
        context.insert(state)
        return state
    }

    // MARK: - Плейлисты

    func reloadPlaylists() {
        let fetched = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
        playlists = fetched.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Создаёт плейлист. Пустое имя не принимается.
    @discardableResult
    func createPlaylist(named name: String) -> Playlist? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let nextIndex = (playlists.map { $0.orderIndex }.max() ?? -1) + 1
        let playlist = Playlist(name: clean, orderIndex: nextIndex)
        context.insert(playlist)
        commit("createPlaylist")
        reloadPlaylists()
        return playlist
    }

    func renamePlaylist(_ playlist: Playlist, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        playlist.name = clean
        commit("renamePlaylist")
        reloadPlaylists()
    }

    /// Удаляет плейлист. Файлы остаются на устройстве.
    func deletePlaylist(_ playlist: Playlist) {
        context.delete(playlist)
        commit("deletePlaylist")
        reloadPlaylists()
    }

    /// Перетаскивание вкладок плейлистов.
    func movePlaylists(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let reordered = FisherYates.moved(playlists, fromOffsets: offsets, toOffset: destination)
        for (index, playlist) in reordered.enumerated() {
            playlist.orderIndex = index
        }
        commit("movePlaylists")
        reloadPlaylists()
    }

    /// Вкладки плейлистов по алфавиту.
    func sortPlaylistsAlphabetically() {
        let sorted = playlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for (index, playlist) in sorted.enumerated() {
            playlist.orderIndex = index
        }
        commit("sortPlaylists")
        reloadPlaylists()
    }

    /// Добавляет треки в плейлист: в начало или в конец — по настройке.
    func add(_ tracks: [TrackRecord], to playlist: Playlist) {
        guard !tracks.isEmpty else { return }
        let indexes = playlist.entries.map { $0.orderIndex }
        var nextIndex: Int
        if AppSettings.insertNewAtStart {
            nextIndex = (indexes.min() ?? 0) - tracks.count
        } else {
            nextIndex = (indexes.max() ?? -1) + 1
        }
        for track in tracks {
            let entry = PlaylistEntry(orderIndex: nextIndex)
            context.insert(entry)
            entry.playlist = playlist
            entry.track = track
            nextIndex += 1
        }
        commit("addToPlaylist")
    }

    /// Убирает строки из плейлиста. Файлы остаются на устройстве.
    func remove(_ entries: [PlaylistEntry]) {
        for entry in entries {
            context.delete(entry)
        }
        commit("removeFromPlaylist")
    }

    /// Убирает трек из плейлиста (все его вхождения).
    func remove(_ track: TrackRecord, from playlist: Playlist) {
        let matching = playlist.entries.filter { $0.track?.uid == track.uid }
        remove(matching)
    }

    // MARK: - «Супер!»

    /// Ставит или снимает отметку «Супер!» (сердечко).
    func toggleSuper(_ track: TrackRecord) {
        track.isSuper.toggle()
        track.superAt = track.isSuper ? Date() : nil
        commit("super")
    }

    // MARK: - Внутреннее

    private func commit(_ reason: String) {
        library.saveContext(reason)
        revision += 1
    }
}
