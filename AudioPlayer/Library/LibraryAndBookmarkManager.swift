import Foundation
import SwiftData
import Observation

/// Библиотека: сканирование Documents, импорт, папки, закладки.
/// Вся работа с базой SwiftData идёт на главном потоке; тяжёлое
/// (обход диска, отпечатки, чтение тегов, копирование) — в фоновых задачах.
@MainActor
@Observable
final class LibraryAndBookmarkManager {
    /// Все треки библиотеки (обновляется после сканирования и изменений).
    private(set) var tracks: [TrackRecord] = []
    /// Идёт сканирование или импорт.
    private(set) var isBusy: Bool = false
    /// Текст о ходе работы для показа в интерфейсе.
    private(set) var progressText: String = ""

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var rescanRequestedWhileBusy = false

    init(context: ModelContext) {
        self.context = context
        reloadTracks()
    }

    // MARK: - Чтение

    /// Перечитывает список треков из базы.
    func reloadTracks() {
        let descriptor = FetchDescriptor<TrackRecord>()
        let fetched = (try? context.fetch(descriptor)) ?? []
        tracks = fetched.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
    }

    /// Треки в папке (относительный путь, "" — корень), по имени файла.
    func tracksInFolder(_ folder: String) -> [TrackRecord] {
        tracks.filter { $0.folderPath == folder }
    }

    /// Подпапки в папке.
    func subfolders(of folder: String) -> [String] {
        LibraryScanner.subfolders(of: folder)
    }

    func track(withUID uid: UUID) -> TrackRecord? {
        tracks.first { $0.uid == uid }
    }

    // MARK: - Сканирование

    /// Сверяет базу с содержимым Documents: новые файлы добавляет,
    /// перемещённые узнаёт по отпечатку, исчезнувшие удаляет из базы.
    func rescan() async {
        if isBusy {
            rescanRequestedWhileBusy = true
            return
        }
        isBusy = true
        progressText = tr("Поиск файлов…")

        let files = await Task.detached(priority: .utility) { () -> [ScannedFile] in
            LibraryScanner.drainInbox()
            return LibraryScanner.scanDocuments()
        }.value

        let existing = (try? context.fetch(FetchDescriptor<TrackRecord>())) ?? []
        var knownPaths = Set<String>()
        for record in existing {
            knownPaths.insert(record.relativePath)
        }
        let foundPaths = Set(files.map { $0.relativePath })

        // Записи, чьи файлы исчезли со своих мест — кандидаты на «переехал»
        var orphans = existing.filter { !foundPaths.contains($0.relativePath) }
        let newFiles = files.filter { !knownPaths.contains($0.relativePath) }

        // Новые файлы встают в начало или в конец списка — по настройке
        var nextOrder: Int
        if AppSettings.insertNewAtStart {
            nextOrder = (existing.map { $0.allOrderIndex }.min() ?? 0) - newFiles.count
        } else {
            nextOrder = (existing.map { $0.allOrderIndex }.max() ?? -1) + 1
        }
        var addedCount = 0
        var relinkedCount = 0

        for (index, file) in newFiles.enumerated() {
            progressText = tr("Добавление %@ из %@…", "\(index + 1)", "\(newFiles.count)")
            let url = LibraryPaths.url(forRelative: file.relativePath)
            let fileName = url.lastPathComponent

            let fingerprint = await Task.detached(priority: .utility) {
                FileFingerprint.compute(url: url)
            }.value ?? ""

            // Тот же файл в новом месте: сохраняем запись со всеми закладками и счётчиками
            if !fingerprint.isEmpty, let orphanIndex = orphans.firstIndex(where: { $0.fingerprint == fingerprint }) {
                let record = orphans.remove(at: orphanIndex)
                record.relativePath = file.relativePath
                record.fileName = fileName
                relinkedCount += 1
                continue
            }

            let metadata = await MetadataExtractor.extract(url: url)
            let record = TrackRecord(
                relativePath: file.relativePath,
                fileName: fileName,
                fingerprint: fingerprint,
                fileSize: file.size
            )
            apply(metadata, to: record)
            record.formatName = AudioFormats.displayName(forExtension: url.pathExtension)
            record.allOrderIndex = nextOrder
            record.folderOrderIndex = nextOrder
            nextOrder += 1
            context.insert(record)
            addedCount += 1

            if let artwork = metadata.artworkData {
                let uid = record.uid
                let stored = await Task.detached(priority: .utility) {
                    ArtworkCache.store(imageData: artwork, for: uid)
                }.value
                record.hasArtwork = stored
            }
        }

        // Файлы, которых больше нет нигде, убираем из базы вместе с закладками
        let removedCount = orphans.count
        for record in orphans {
            ArtworkCache.remove(for: record.uid)
            context.delete(record)
        }

        saveContext("rescan")
        reloadTracks()

        if addedCount > 0 || relinkedCount > 0 || removedCount > 0 {
            AppLogger.shared.log(
                "scan",
                tr("Найдено файлов: %@; добавлено: %@; перемещено: %@; удалено из базы: %@", "\(files.count)", "\(addedCount)", "\(relinkedCount)", "\(removedCount)")
            )
        }

        progressText = ""
        isBusy = false

        if rescanRequestedWhileBusy {
            rescanRequestedWhileBusy = false
            await rescan()
        }
    }

    /// Заново извлекает обложки для треков, у которых они пропали из кэша
    /// (например, после «Очистить кэш обложек»).
    func restoreMissingArtwork() async {
        for record in tracks where record.hasArtwork {
            let uid = record.uid
            if ArtworkCache.exists(for: uid) { continue }
            let url = record.fileURL
            let metadata = await MetadataExtractor.extract(url: url)
            guard let artwork = metadata.artworkData else {
                record.hasArtwork = false
                continue
            }
            let stored = await Task.detached(priority: .utility) {
                ArtworkCache.store(imageData: artwork, for: uid)
            }.value
            record.hasArtwork = stored
        }
        saveContext("artwork")
    }

    // MARK: - Импорт

    /// Копирует выбранные файлы в папку библиотеки и добавляет их в базу.
    func importFiles(_ urls: [URL], intoFolder folder: String = "") async -> ImportReport {
        var report = ImportReport()
        for (index, source) in urls.enumerated() {
            progressText = tr("Копирование %@ из %@…", "\(index + 1)", "\(urls.count)")
            let name = source.lastPathComponent

            // Файл уже лежит в библиотеке (например, открыт из папки приложения)
            if LibraryPaths.relativePath(for: source) != nil {
                continue
            }
            guard AudioFormats.isSupported(source) else {
                report.skipped.append(name)
                continue
            }
            let result = await Task.detached(priority: .userInitiated) {
                FileImportService.copyIntoLibrary(source: source, folder: folder)
            }.value
            switch result {
            case .success(let savedName):
                report.added.append(savedName)
            case .failure(let failure):
                report.failed.append("\(name) — \(failure.message)")
                AppLogger.shared.log("import", "Ошибка импорта \(name): \(failure.message)")
            }
        }
        progressText = ""
        await rescan()

        // Дубликаты запрещены: новый файл, который повторяет уже существующий, удаляем
        if !AppSettings.allowDuplicates, !report.added.isEmpty {
            let addedPaths = Set(report.added.map { LibraryPaths.join(folder, $0) })
            let newTracks = tracks.filter { addedPaths.contains($0.relativePath) }
            let oldTracks = tracks.filter { !addedPaths.contains($0.relativePath) }
            for newTrack in newTracks {
                guard let existing = oldTracks.first(where: { isDuplicate(newTrack, $0) }) else { continue }
                report.duplicates.append(DuplicateInfo(
                    title: existing.displayTitle,
                    artist: existing.artist,
                    existingUID: existing.uid,
                    listKey: "all",
                    listName: tr("Все треки")
                ))
                report.added.removeAll { $0 == newTrack.fileName }
                deleteFromDevice(newTrack)
            }
        }

        if !report.isEmpty {
            AppLogger.shared.log(
                "import",
                tr("Импорт: добавлено %@, пропущено %@, ошибок %@", "\(report.added.count)", "\(report.skipped.count)", "\(report.failed.count)")
            )
        }
        return report
    }

    // MARK: - Папки и файлы

    /// Создаёт папку. Возвращает false, если не получилось.
    @discardableResult
    func createFolder(named name: String, in parent: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/") else { return false }
        let url = LibraryPaths.url(forRelative: LibraryPaths.join(parent, clean))
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            AppLogger.shared.log("files", "Не удалось создать папку \(clean): \(error.localizedDescription)")
            return false
        }
    }

    /// Переименовывает файл трека. `newBaseName` — имя без расширения.
    /// Запись, закладки, счётчики и плейлисты сохраняются.
    @discardableResult
    func renameFile(of track: TrackRecord, toBaseName newBaseName: String) -> Bool {
        let clean = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/") else { return false }
        let ext = (track.fileName as NSString).pathExtension
        let newName = ext.isEmpty ? clean : "\(clean).\(ext)"
        if newName == track.fileName { return true }
        let folder = track.folderPath
        let newRelative = LibraryPaths.join(folder, newName)
        let target = LibraryPaths.url(forRelative: newRelative)
        guard !FileManager.default.fileExists(atPath: target.path) else { return false }
        do {
            try FileManager.default.moveItem(at: track.fileURL, to: target)
            track.relativePath = newRelative
            track.fileName = newName
            saveContext("rename")
            reloadTracks()
            return true
        } catch {
            AppLogger.shared.log("files", "Не удалось переименовать \(track.fileName): \(error.localizedDescription)")
            return false
        }
    }

    /// Перемещает файл трека в другую папку.
    @discardableResult
    func move(_ track: TrackRecord, toFolder folder: String) -> Bool {
        if track.folderPath == folder { return true }
        let name = LibraryPaths.uniqueName(for: track.fileName, inFolder: folder)
        let newRelative = LibraryPaths.join(folder, name)
        let target = LibraryPaths.url(forRelative: newRelative)
        do {
            try FileManager.default.createDirectory(
                at: LibraryPaths.url(forRelative: folder),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: track.fileURL, to: target)
            track.relativePath = newRelative
            track.fileName = name
            saveContext("move")
            reloadTracks()
            return true
        } catch {
            AppLogger.shared.log("files", "Не удалось переместить \(track.fileName): \(error.localizedDescription)")
            return false
        }
    }

    /// Удаляет файл с устройства и запись из базы (с закладками и строками плейлистов).
    /// Вызывать только после подтверждения пользователя.
    @discardableResult
    func deleteFromDevice(_ track: TrackRecord) -> Bool {
        let url = track.fileURL
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        } catch {
            AppLogger.shared.log("files", "Не удалось удалить \(track.fileName): \(error.localizedDescription)")
            return false
        }
        ArtworkCache.remove(for: track.uid)
        context.delete(track)
        saveContext("delete")
        reloadTracks()
        return true
    }

    /// Удаляет папку со всем содержимым. Вызывать только после подтверждения.
    @discardableResult
    func deleteFolder(_ folder: String) async -> Bool {
        guard !folder.isEmpty else { return false }
        do {
            try FileManager.default.removeItem(at: LibraryPaths.url(forRelative: folder))
        } catch {
            AppLogger.shared.log("files", "Не удалось удалить папку \(folder): \(error.localizedDescription)")
            return false
        }
        await rescan()
        return true
    }

    // MARK: - Дубликаты

    /// Дубликат: тот же файл по содержимому, или те же исполнитель и название
    /// при разнице длительности не больше ±2 секунд.
    func isDuplicate(_ a: TrackRecord, _ b: TrackRecord) -> Bool {
        if a.uid == b.uid { return false }
        if !a.fingerprint.isEmpty && a.fingerprint == b.fingerprint { return true }
        let titleA = normalized(a.displayTitle)
        let titleB = normalized(b.displayTitle)
        guard !titleA.isEmpty, titleA == titleB else { return false }
        guard normalized(a.artist) == normalized(b.artist) else { return false }
        return abs(a.duration - b.duration) <= 2
    }

    /// Группы дубликатов во всей библиотеке (в группе — 2 и больше треков).
    func duplicateGroups() -> [[TrackRecord]] {
        var groups: [[TrackRecord]] = []
        var used = Set<UUID>()
        for track in tracks where !used.contains(track.uid) {
            let group = [track] + tracks.filter { other in
                !used.contains(other.uid) && isDuplicate(track, other)
            }
            if group.count > 1 {
                groups.append(group)
                group.forEach { used.insert($0.uid) }
            }
        }
        return groups
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Теги

    /// Обновляет теги в базе после редактирования.
    func applyTags(_ tags: TagValues, to track: TrackRecord) {
        track.title = tags.title.trimmingCharacters(in: .whitespacesAndNewlines)
        track.artist = tags.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        track.album = tags.album.trimmingCharacters(in: .whitespacesAndNewlines)
        track.albumArtist = tags.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        track.genre = tags.genre.trimmingCharacters(in: .whitespacesAndNewlines)
        track.year = tags.year.trimmingCharacters(in: .whitespacesAndNewlines)
        track.trackNumber = tags.trackNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        track.composer = tags.composer.trimmingCharacters(in: .whitespacesAndNewlines)
        track.comment = tags.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        // Файл изменился — обновляем отпечаток и размер
        if let fingerprint = FileFingerprint.compute(url: track.fileURL) {
            track.fingerprint = fingerprint
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: track.fileURL.path),
           let size = attrs[.size] as? NSNumber {
            track.fileSize = size.int64Value
        }
        saveContext("tags")
        reloadTracks()
    }

    /// Меняет обложку в кэше (nil — удалить).
    func setArtwork(_ data: Data?, for track: TrackRecord) {
        if let data {
            track.hasArtwork = ArtworkCache.store(imageData: data, for: track.uid)
        } else {
            ArtworkCache.remove(for: track.uid)
            track.hasArtwork = false
        }
        saveContext("artwork")
    }

    // MARK: - Аудиокниги

    /// Аудиокнига: .m4b всегда; файл не короче порога (по умолчанию 20 мин);
    /// файл в папке, помеченной «Аудиокниги» (или в её подпапке).
    func isAudiobook(_ track: TrackRecord) -> Bool {
        let ext = (track.fileName as NSString).pathExtension.lowercased()
        if ext == "m4b" { return true }
        if track.duration >= Double(AppSettings.audiobookThresholdMinutes * 60) { return true }
        let folders = audiobookFolders()
        guard !folders.isEmpty else { return false }
        let path = track.folderPath
        return folders.contains { marked in path == marked || path.hasPrefix(marked + "/") }
    }

    /// Папки, помеченные как «Аудиокниги».
    func audiobookFolders() -> [String] {
        let states = (try? context.fetch(FetchDescriptor<ListState>())) ?? []
        return states
            .filter { $0.isAudiobookFolder && $0.key.hasPrefix("folder:") }
            .map { String($0.key.dropFirst("folder:".count)) }
    }

    func isAudiobookFolder(_ path: String) -> Bool {
        audiobookFolders().contains(path)
    }

    /// Помечает папку как «Аудиокниги» (или снимает отметку).
    func setAudiobookFolder(_ path: String, _ value: Bool) {
        let key = "folder:" + path
        let states = (try? context.fetch(FetchDescriptor<ListState>())) ?? []
        if let state = states.first(where: { $0.key == key }) {
            state.isAudiobookFolder = value
        } else {
            let state = ListState(key: key)
            state.isAudiobookFolder = value
            context.insert(state)
        }
        saveContext("audiobookFolder")
    }

    // MARK: - Закладки

    /// Добавляет закладку на заданной секунде трека.
    @discardableResult
    func addBookmark(to track: TrackRecord, time: Double, note: String) -> Bookmark {
        let bookmark = Bookmark(time: max(0, time), note: note)
        context.insert(bookmark)
        bookmark.track = track
        saveContext("bookmark")
        return bookmark
    }

    func updateBookmark(_ bookmark: Bookmark, note: String) {
        bookmark.note = note
        saveContext("bookmark")
    }

    func deleteBookmark(_ bookmark: Bookmark) {
        context.delete(bookmark)
        saveContext("bookmark")
    }

    /// Закладки трека по возрастанию времени.
    func bookmarks(of track: TrackRecord) -> [Bookmark] {
        track.bookmarks.sorted { $0.time < $1.time }
    }

    // MARK: - Сохранение

    /// Сохраняет изменения в базе; ошибку пишет в журнал.
    func saveContext(_ reason: String) {
        do {
            try context.save()
        } catch {
            AppLogger.shared.log("db", "Ошибка сохранения (\(reason)): \(error.localizedDescription)")
        }
    }

    // MARK: - Внутреннее

    private func apply(_ metadata: ExtractedMetadata, to record: TrackRecord) {
        record.title = metadata.title
        record.artist = metadata.artist
        record.album = metadata.album
        record.albumArtist = metadata.albumArtist
        record.genre = metadata.genre
        record.year = metadata.year
        record.trackNumber = metadata.trackNumber
        record.composer = metadata.composer
        record.comment = metadata.comment
        record.duration = metadata.duration
        record.bitrateKbps = metadata.bitrateKbps
        record.sampleRate = metadata.sampleRate
        record.isProtected = metadata.isProtected
        record.isPlayable = metadata.isPlayable
    }
}
