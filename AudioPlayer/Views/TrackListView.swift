import SwiftUI

/// Нижняя часть главного экрана: поиск, кнопки порядка, список треков.
///
/// Поиск ничего не скрывает: после каждой буквы или цифры список прокручивается
/// к первому совпадению, подсвечивает его и ставит в центр. Цифры — номер строки,
/// текст — исполнитель, название или имя файла. Return — следующее совпадение.
struct TrackListView: View {
    let container: AppContainer
    let list: ListID
    let onOpenFolder: (String) -> Void
    let onMenu: (TrackRecord, PlaylistEntry?) -> Void
    let onRequestDelete: ([TrackRecord]) -> Void
    let onAddToPlaylist: ([TrackRecord]) -> Void
    let onToast: (String) -> Void

    @Environment(\.palette) private var palette
    @AppStorage(SettingsKeys.showHeart) private var showHeart = true
    @AppStorage(SettingsKeys.showPlayCount) private var showPlayCount = true

    @State private var query = ""
    @State private var matchCursor = 0
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var folderToDelete: String?
    @FocusState private var searchFocused: Bool

    private var lists: QueueAndPlaylistManager { container.lists }
    private var playback: PlaybackController { container.playback }

    private var folderPath: String? {
        if case .folder(let path) = list { return path }
        return nil
    }

    // MARK: - Данные

    private var rows: [ListRowItem] {
        if case .playlist = list {
            return lists.entries(for: list).enumerated().compactMap { index, entry in
                guard let track = entry.track else { return nil }
                return ListRowItem(id: entry.uid, track: track, entry: entry, number: index + 1)
            }
        }
        return lists.tracks(for: list).enumerated().map { index, track in
            ListRowItem(id: track.uid, track: track, entry: nil, number: index + 1)
        }
    }

    private var subfolders: [String] {
        guard let folderPath else { return [] }
        _ = container.library.tracks.count
        return container.library.subfolders(of: folderPath)
    }

    /// Перетаскивание строк — только там, где порядок ручной (не в ★ и ♥).
    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard list.isReorderable else { return nil }
        let currentList = list
        let manager = lists
        return { offsets, destination in
            manager.move(in: currentList, fromOffsets: offsets, toOffset: destination)
        }
    }

    /// Номера строк (индексы в rows), подходящие под запрос.
    private func matches(in rows: [ListRowItem]) -> [Int] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        if q.allSatisfy({ $0.isNumber }), let number = Int(q) {
            return rows.indices.filter { rows[$0].number == number }
        }
        return rows.indices.filter { index in
            let track = rows[index].track
            let haystack = (track.artist + " " + track.displayTitle + " " + track.fileName).lowercased()
            return haystack.contains(q)
        }
    }

    // MARK: - Экран

    var body: some View {
        let rows = self.rows
        let found = matches(in: rows)
        let cursor = found.isEmpty ? 0 : min(matchCursor, found.count - 1)
        let foundID = found.isEmpty ? nil : rows[found[cursor]].id

        VStack(spacing: 0) {
            searchBar
            if let folderPath {
                folderBar(folderPath)
            }
            statusLine(rows: rows, found: found, cursor: cursor)

            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(subfolders, id: \.self) { name in
                        folderRow(name)
                    }
                    ForEach(rows) { item in
                        row(item, isFound: item.id == foundID)
                            .id(item.id)
                    }
                    .onMove(perform: moveAction)

                    if rows.isEmpty && subfolders.isEmpty {
                        Text(emptyText)
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .selectionDisabled()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, $editMode)
                .refreshable {
                    await container.library.rescan()
                }
                .onAppear {
                    scrollToCurrent(proxy: proxy, rows: rows, animated: false)
                }
                .onChange(of: playback.currentTrack?.uid) { _, _ in
                    if query.isEmpty {
                        scrollToCurrent(proxy: proxy, rows: self.rows, animated: true)
                    }
                }
                .onChange(of: list) { _, _ in
                    query = ""
                    selection = []
                    editMode = .inactive
                    scrollToCurrent(proxy: proxy, rows: self.rows, animated: false)
                }
                .onChange(of: query) { _, _ in
                    matchCursor = 0
                    let currentRows = self.rows
                    let currentFound = matches(in: currentRows)
                    if let first = currentFound.first {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(currentRows[first].id, anchor: .center)
                        }
                    } else if query.isEmpty {
                        scrollToCurrent(proxy: proxy, rows: currentRows, animated: true)
                    }
                }
                .onChange(of: matchCursor) { _, newValue in
                    let currentRows = self.rows
                    let currentFound = matches(in: currentRows)
                    guard !currentFound.isEmpty else { return }
                    let index = currentFound[min(newValue, currentFound.count - 1)]
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(currentRows[index].id, anchor: .center)
                    }
                }
                .onChange(of: rows.map(\.track.uid)) { _, newValue in
                    // Список изменился — очередь воспроизведения подстраивается
                    playback.syncQueue(items: newValue, contextKey: list.key)
                }
            }

            if editMode.isEditing {
                selectionBar(rows: rows)
            }
        }
        .alert("Новая папка", isPresented: $showNewFolder) {
            TextField("Название", text: $newFolderName)
            Button("Создать") {
                if let folderPath, container.library.createFolder(named: newFolderName, in: folderPath) {
                    onToast("Папка «\(newFolderName)» создана")
                }
                newFolderName = ""
            }
            Button("Отмена", role: .cancel) {
                newFolderName = ""
            }
        }
        .alert(
            "Удалить папку?",
            isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
            presenting: folderToDelete
        ) { path in
            Button("Удалить", role: .destructive) {
                Task {
                    _ = await container.library.deleteFolder(path)
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: { path in
            Text("Папка «\((path as NSString).lastPathComponent)» и все файлы в ней будут удалены с iPhone. Отменить нельзя.")
        }
    }

    // MARK: - Поиск и кнопки

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.secondaryText)
                TextField("Название или № строки", text: $query)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit {
                        // Return — к следующему совпадению
                        matchCursor += 1
                        let count = matches(in: rows).count
                        if count > 0 { matchCursor %= count }
                        searchFocused = true
                    }
                    .foregroundStyle(palette.text)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.secondaryText)
                    }
                    .accessibilityLabel("Очистить поиск")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(palette.button))

            smallButton(systemImage: "shuffle", label: "Перемешать список") {
                lists.shuffleList(list)
                onToast("Список перемешан")
            }
            .disabled(!list.isReorderable)

            Button {
                lists.sortAlphabetically(list)
                onToast("По алфавиту")
            } label: {
                Text("А–Я")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.text)
                    .frame(width: 44, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(palette.button))
            }
            .buttonStyle(.plain)
            .disabled(!list.isReorderable)
            .accessibilityLabel("Сортировать по алфавиту")

            Button {
                withAnimation {
                    editMode = editMode.isEditing ? .inactive : .active
                    selection = []
                }
            } label: {
                Image(systemName: editMode.isEditing ? "checkmark.circle.fill" : "checklist")
                    .font(.system(size: 17))
                    .foregroundStyle(editMode.isEditing ? palette.accent : palette.text)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(palette.button))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(editMode.isEditing ? "Готово" : "Выбрать несколько")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func smallButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(palette.button))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func statusLine(rows: [ListRowItem], found: [Int], cursor: Int) -> some View {
        HStack {
            Text(leftStatus(rows: rows, found: found, cursor: cursor))
            Spacer()
            Text(rightStatus(rows: rows))
        }
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func leftStatus(rows: [ListRowItem], found: [Int], cursor: Int) -> String {
        if !query.isEmpty {
            if found.isEmpty { return "Ничего не найдено" }
            return "Совпадений: \(found.count) · показано \(cursor + 1)-е"
        }
        switch list {
        case .hitParade: return "★ По популярности"
        case .superList: return "♥ Супер!: \(rows.count)"
        default: return "Треков: \(rows.count)"
        }
    }

    private func rightStatus(rows: [ListRowItem]) -> String {
        if list == .hitParade {
            let plays = rows.reduce(0) { $0 + $1.track.playCount }
            return "Прослушиваний: \(plays)"
        }
        let total = rows.reduce(0.0) { $0 + $1.track.duration }
        return "Общее время \(TimeText.format(total))"
    }

    private var emptyText: String {
        switch list {
        case .hitParade: return "Здесь появятся треки, которые вы слушаете чаще всего"
        case .superList: return "Нажмите ♥ у трека — он появится здесь"
        case .all: return "Нажмите + чтобы добавить музыку"
        case .folder: return "В этой папке нет музыки"
        case .playlist: return "Плейлист пуст. Добавьте треки через ⚙ → «Добавить в плейлист»"
        }
    }

    // MARK: - Папки

    private func folderBar(_ path: String) -> some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Button("Музыка") { onOpenFolder("") }
                    let parts = path.split(separator: "/").map(String.init)
                    ForEach(parts.indices, id: \.self) { index in
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondaryText)
                        Button(parts[index]) {
                            onOpenFolder(parts[0...index].joined(separator: "/"))
                        }
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.accent)
            }
            Button {
                showNewFolder = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .foregroundStyle(palette.text)
                    .frame(width: 40, height: 32)
            }
            .accessibilityLabel("Новая папка")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func folderRow(_ name: String) -> some View {
        let full = LibraryPaths.join(folderPath ?? "", name)
        return Button {
            onOpenFolder(full)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(palette.accent)
                    .frame(width: 32)
                Text(name)
                    .foregroundStyle(palette.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)
            }
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(palette.line)
        .selectionDisabled()
        .contextMenu {
            let isBooks = container.library.isAudiobookFolder(full)
            Button {
                container.library.setAudiobookFolder(full, !isBooks)
                onToast(isBooks ? "Отметка «Аудиокниги» снята" : "Папка помечена как «Аудиокниги»")
            } label: {
                Label(isBooks ? "Снять отметку «Аудиокниги»" : "Пометить как «Аудиокниги»", systemImage: "book")
            }
            Button(role: .destructive) {
                folderToDelete = full
            } label: {
                Label("Удалить папку с устройства…", systemImage: "trash")
            }
        }
    }

    // MARK: - Строки

    private func row(_ item: ListRowItem, isFound: Bool) -> some View {
        let isCurrent = item.track.uid == playback.currentTrack?.uid
        return TrackRow(
            item: item,
            isCurrent: isCurrent,
            isPlaying: playback.isPlaying,
            showHeart: showHeart,
            showPlayCount: showPlayCount,
            onPlay: { play(item) },
            onToggleSuper: { lists.toggleSuper(item.track) },
            onMenu: { onMenu(item.track, item.entry) }
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 6))
        .listRowSeparatorTint(palette.line)
        .listRowBackground(
            Rectangle()
                .fill(isFound ? palette.rowFound : (isCurrent ? palette.rowCurrent : Color.clear))
                .overlay(Rectangle().stroke(isFound ? palette.accent : .clear, lineWidth: 2))
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                onRequestDelete([item.track])
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            .tint(Palette.danger)
            if let entry = item.entry {
                Button {
                    lists.remove([entry])
                    onToast("Убрано из плейлиста")
                } label: {
                    Label("Убрать", systemImage: "minus.circle")
                }
                .tint(.gray)
            }
        }
        .contextMenu {
            Button {
                lists.toggleSuper(item.track)
            } label: {
                Label(item.track.isSuper ? "Убрать из «Супер!»" : "Супер!", systemImage: "heart")
            }
            Button {
                onAddToPlaylist([item.track])
            } label: {
                Label("Добавить в плейлист…", systemImage: "text.badge.plus")
            }
            if let entry = item.entry {
                Button {
                    lists.remove([entry])
                    onToast("Убрано из плейлиста")
                } label: {
                    Label("Убрать из этого плейлиста", systemImage: "minus.circle")
                }
            }
            Button {
                onMenu(item.track, item.entry)
            } label: {
                Label("Все действия…", systemImage: "gearshape")
            }
            Button(role: .destructive) {
                onRequestDelete([item.track])
            } label: {
                Label("Удалить с устройства…", systemImage: "trash")
            }
        }
    }

    private func play(_ item: ListRowItem) {
        if item.track.isProtected || !item.track.isPlayable {
            onToast("Файл защищён (DRM) и не может быть воспроизведён")
            return
        }
        let uids = rows.map(\.track.uid)
        playback.play(items: uids, startUID: item.track.uid, contextKey: list.key)
        query = ""
        searchFocused = false
    }

    private func scrollToCurrent(proxy: ScrollViewProxy, rows: [ListRowItem], animated: Bool) {
        guard let uid = playback.currentTrack?.uid,
              let row = rows.first(where: { $0.track.uid == uid }) else { return }
        // Небольшая задержка: список должен успеть построиться
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(animated ? 50 : 250))
            if animated {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(row.id, anchor: .center)
                }
            } else {
                proxy.scrollTo(row.id, anchor: .center)
            }
        }
    }

    // MARK: - Мультивыбор

    private func selectionBar(rows: [ListRowItem]) -> some View {
        let chosen = rows.filter { selection.contains($0.id) }
        return HStack(spacing: 10) {
            Text("Выбрано: \(chosen.count)")
                .font(.footnote)
                .foregroundStyle(palette.secondaryText)
            Spacer()
            Button("В плейлист") {
                onAddToPlaylist(chosen.map(\.track))
            }
            .disabled(chosen.isEmpty)
            if case .playlist = list {
                Button("Убрать") {
                    lists.remove(chosen.compactMap(\.entry))
                    onToast("Убрано из плейлиста: \(chosen.count)")
                    selection = []
                }
                .disabled(chosen.isEmpty)
            }
            Button("Удалить") {
                onRequestDelete(chosen.map(\.track))
                selection = []
            }
            .foregroundStyle(Palette.danger)
            .disabled(chosen.isEmpty)
        }
        .font(.system(size: 15, weight: .semibold))
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(palette.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.line).frame(height: 1)
        }
    }
}
