import SwiftUI
import UniformTypeIdentifiers

/// Главный экран: сверху панель плеера, снизу вкладки и список треков.
struct ContentView: View {
    let container: AppContainer

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingsKeys.accentHex) private var accentHex = Palette.defaultAccentHex
    @AppStorage(SettingsKeys.lastListKey) private var lastListKey = ListID.all.key
    @AppStorage(SettingsKeys.lastFolder) private var lastFolder = ""
    @AppStorage(SettingsKeys.rememberFolder) private var rememberFolder = true
    @AppStorage(SettingsKeys.showHitTab) private var showHitTab = true
    @AppStorage(SettingsKeys.showSuperTab) private var showSuperTab = true

    @State private var selectedList: ListID = .all
    @State private var didRestoreList = false
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var menuTarget: MenuTarget?
    @State private var addTarget: AddTarget?
    @State private var pendingDelete: [TrackRecord] = []
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var playlistToRename: Playlist?
    @State private var renameText = ""
    @State private var playlistToDelete: Playlist?
    @State private var toast: String?
    @State private var showEqualizer = false
    @State private var showSleepTimer = false
    @State private var showBookmarks = false
    @State private var showChapters = false
    @State private var bookmarkForNote: Bookmark?
    @State private var bookmarkNote = ""
    @State private var toastTask: Task<Void, Never>?

    private var palette: Palette {
        Palette.make(dark: colorScheme == .dark, accentHex: accentHex)
    }

    private var playback: PlaybackController { container.playback }
    private var lists: QueueAndPlaylistManager { container.lists }

    var body: some View {
        VStack(spacing: 0) {
            PlayerPanel(
                playback: playback,
                currentRowNumber: currentRowNumber,
                onImport: { showImporter = true },
                onSettings: { showSettings = true },
                onBookmark: addBookmark,
                onBookmarksList: { showBookmarks = true },
                onEqualizer: { showEqualizer = true },
                onSleepTimer: { showSleepTimer = true },
                onChapters: { showChapters = true }
            )
            ListTabsBar(
                selected: $selectedList,
                playlists: lists.playlists,
                currentFolder: rememberFolder ? lastFolder : "",
                onCreate: { showNewPlaylist = true },
                onRename: { playlist in
                    renameText = playlist.name
                    playlistToRename = playlist
                },
                onDelete: { playlist in
                    playlistToDelete = playlist
                },
                onMove: movePlaylist
            )
            TrackListView(
                container: container,
                list: selectedList,
                onOpenFolder: { path in
                    selectedList = .folder(path)
                },
                onMenu: { track, entry in
                    menuTarget = MenuTarget(track: track, entry: entry)
                },
                onRequestDelete: { tracks in
                    requestDelete(tracks)
                },
                onAddToPlaylist: { tracks in
                    addTarget = AddTarget(tracks: tracks)
                },
                onToast: showToast
            )
        }
        .background(palette.background.ignoresSafeArea())
        .environment(\.palette, palette)
        .tint(palette.accent)
        .overlay(alignment: .bottom) {
            toastView
        }
        .onAppear(perform: restoreSelectedList)
        .onChange(of: selectedList) { _, newValue in
            lastListKey = newValue.key
            if case .folder(let path) = newValue {
                lastFolder = path
            }
        }
        .onChange(of: showHitTab) { _, visible in
            if !visible, selectedList == .hitParade { selectedList = .all }
        }
        .onChange(of: showSuperTab) { _, visible in
            if !visible, selectedList == .superList { selectedList = .all }
        }
        .onChange(of: lists.playlists.map(\.uid)) { _, uids in
            // Открытый плейлист удалили — переходим во «Все треки»
            if case .playlist(let uid) = selectedList, !uids.contains(uid) {
                selectedList = .all
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: AudioFormats.importTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(item: $menuTarget) { target in
            FileActionsSheet(
                track: target.track,
                entry: target.entry,
                rowNumber: rowNumber(of: target.track),
                onToggleSuper: { lists.toggleSuper(target.track) },
                onAddToPlaylist: {
                    afterSheetCloses { addTarget = AddTarget(tracks: [target.track]) }
                },
                onRemoveFromPlaylist: {
                    if let entry = target.entry {
                        lists.remove([entry])
                        showToast("Убрано из плейлиста")
                    }
                },
                onDelete: {
                    afterSheetCloses { requestDelete([target.track]) }
                }
            )
            .environment(\.palette, palette)
        }
        .sheet(item: $addTarget) { target in
            AddToPlaylistSheet(lists: lists, tracks: target.tracks, onDone: showToast)
        }
        .sheet(isPresented: $showEqualizer) {
            EqualizerView(equalizer: container.equalizer)
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerView(timer: playback.sleepTimer)
                .environment(\.palette, palette)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(container: container)
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showChapters) {
            ChaptersView(playback: playback)
                .environment(\.palette, palette)
                .presentationDetents([.medium, .large])
        }
        .alert(
            "Закладка на \(TimeText.format(bookmarkForNote?.time ?? 0))",
            isPresented: Binding(get: { bookmarkForNote != nil }, set: { if !$0 { bookmarkForNote = nil } })
        ) {
            TextField("Заметка (можно пропустить)", text: $bookmarkNote)
            Button("Сохранить") {
                if let bookmark = bookmarkForNote, !bookmarkNote.isEmpty {
                    container.library.updateBookmark(bookmark, note: bookmarkNote)
                }
                bookmarkNote = ""
                bookmarkForNote = nil
            }
            Button("Без заметки", role: .cancel) {
                bookmarkNote = ""
                bookmarkForNote = nil
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(container: container)
                .environment(\.palette, palette)
        }
        .alert(
            pendingDelete.count == 1 ? "Удалить файл с устройства?" : "Удалить файлы с устройства?",
            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } })
        ) {
            Button("Удалить", role: .destructive) {
                performDelete()
            }
            Button("Отмена", role: .cancel) {
                pendingDelete = []
            }
        } message: {
            Text(deleteMessage)
        }
        .alert("Новый плейлист", isPresented: $showNewPlaylist) {
            TextField("Название", text: $newPlaylistName)
            Button("Создать") {
                if let playlist = lists.createPlaylist(named: newPlaylistName) {
                    selectedList = .playlist(playlist.uid)
                }
                newPlaylistName = ""
            }
            Button("Отмена", role: .cancel) {
                newPlaylistName = ""
            }
        }
        .alert(
            "Переименовать плейлист",
            isPresented: Binding(get: { playlistToRename != nil }, set: { if !$0 { playlistToRename = nil } })
        ) {
            TextField("Название", text: $renameText)
            Button("Сохранить") {
                if let playlist = playlistToRename {
                    lists.renamePlaylist(playlist, to: renameText)
                }
                playlistToRename = nil
            }
            Button("Отмена", role: .cancel) {
                playlistToRename = nil
            }
        }
        .alert(
            "Удалить плейлист?",
            isPresented: Binding(get: { playlistToDelete != nil }, set: { if !$0 { playlistToDelete = nil } }),
            presenting: playlistToDelete
        ) { playlist in
            Button("Удалить", role: .destructive) {
                lists.deletePlaylist(playlist)
                playlistToDelete = nil
            }
            Button("Отмена", role: .cancel) {
                playlistToDelete = nil
            }
        } message: { playlist in
            Text("Плейлист «\(playlist.name)» будет удалён. Файлы останутся на устройстве.")
        }
        .alert(
            "PlayMyDisk",
            isPresented: Binding(get: { playback.message != nil }, set: { if !$0 { playback.message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playback.message ?? "")
        }
    }

    // MARK: - Вспомогательные типы

    struct MenuTarget: Identifiable {
        let id = UUID()
        let track: TrackRecord
        let entry: PlaylistEntry?
    }

    struct AddTarget: Identifiable {
        let id = UUID()
        let tracks: [TrackRecord]
    }

    // MARK: - Номера строк

    private func rowNumber(of track: TrackRecord) -> Int? {
        lists.tracks(for: selectedList).firstIndex(where: { $0.uid == track.uid }).map { $0 + 1 }
    }

    private var currentRowNumber: Int? {
        guard let track = playback.currentTrack else { return nil }
        return rowNumber(of: track)
    }

    // MARK: - Действия

    private func restoreSelectedList() {
        guard !didRestoreList else { return }
        didRestoreList = true
        guard let saved = ListID(key: lastListKey) else { return }
        switch saved {
        case .folder:
            selectedList = .folder(rememberFolder ? lastFolder : "")
        case .playlist(let uid):
            selectedList = lists.playlist(withUID: uid) != nil ? saved : .all
        case .hitParade:
            selectedList = showHitTab ? saved : .all
        case .superList:
            selectedList = showSuperTab ? saved : .all
        case .all:
            selectedList = .all
        }
    }

    private func movePlaylist(_ uid: UUID, onto target: UUID) {
        guard let from = lists.playlists.firstIndex(where: { $0.uid == uid }),
              let to = lists.playlists.firstIndex(where: { $0.uid == target }) else { return }
        let destination = to > from ? to + 1 : to
        lists.movePlaylists(fromOffsets: IndexSet(integer: from), toOffset: destination)
    }

    private func addBookmark() {
        guard let track = playback.currentTrack else { return }
        let time = playback.engine.computeCurrentTime()
        bookmarkNote = ""
        bookmarkForNote = container.library.addBookmark(to: track, time: time, note: "")
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var folder = ""
            if case .folder(let path) = selectedList { folder = path }
            Task {
                let report = await container.library.importFiles(urls, intoFolder: folder)
                if let text = describe(report) {
                    showToast(text)
                }
            }
        case .failure(let error):
            showToast("Не удалось выбрать файлы: \(error.localizedDescription)")
        }
    }

    private func describe(_ report: ImportReport) -> String? {
        if report.isEmpty { return nil }
        var parts = ["Добавлено: \(report.added.count)"]
        if !report.skipped.isEmpty { parts.append("пропущено: \(report.skipped.count)") }
        if !report.failed.isEmpty { parts.append("ошибок: \(report.failed.count)") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Удаление

    private func requestDelete(_ tracks: [TrackRecord]) {
        guard !tracks.isEmpty else { return }
        pendingDelete = tracks
    }

    private var deleteMessage: String {
        if pendingDelete.count == 1, let track = pendingDelete.first {
            let artist = track.artist.isEmpty ? "" : track.artist + " — "
            return "«\(artist)\(track.displayTitle)» будет удалён с iPhone и из всех плейлистов. Закладки и счётчик прослушиваний тоже удалятся. Отменить нельзя."
        }
        return "Файлов: \(pendingDelete.count). Они будут удалены с iPhone и из всех плейлистов вместе с закладками и счётчиками. Отменить нельзя."
    }

    private func performDelete() {
        let tracks = pendingDelete
        pendingDelete = []
        var deleted = 0
        for track in tracks {
            playback.handleDeleted(uid: track.uid)
            if container.library.deleteFromDevice(track) {
                deleted += 1
            }
        }
        showToast(deleted == tracks.count ? "Удалено: \(deleted)" : "Удалено \(deleted) из \(tracks.count), подробности в журнале")
    }

    /// Следующее окно открываем после закрытия текущего листа.
    private func afterSheetCloses(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            action()
        }
    }

    // MARK: - Всплывающая подсказка

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation { toast = text }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(palette.panel).shadow(color: .black.opacity(0.3), radius: 8, y: 3))
                .overlay(Capsule().stroke(palette.line, lineWidth: 1))
                .padding(.bottom, 24)
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
        }
    }
}
