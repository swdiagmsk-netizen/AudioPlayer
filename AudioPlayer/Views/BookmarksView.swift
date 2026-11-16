import SwiftUI

/// Закладки: текущего трека или всех треков (по файлам).
/// Нажатие — переход к закладке, свайп — удаление, долгое нажатие — изменить заметку.
struct BookmarksView: View {
    let container: AppContainer

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var showAll = false
    @State private var editing: Bookmark?
    @State private var noteText = ""
    @State private var refresh = 0

    private var playback: PlaybackController { container.playback }

    var body: some View {
        NavigationStack {
            List {
                if showAll {
                    let tracks = container.library.tracks.filter { !$0.bookmarks.isEmpty }
                    if tracks.isEmpty {
                        emptyRow
                    }
                    ForEach(tracks, id: \.uid) { track in
                        Section(track.displayTitle) {
                            bookmarkRows(container.library.bookmarks(of: track), track: track)
                        }
                    }
                } else if let track = playback.currentTrack {
                    let items = container.library.bookmarks(of: track)
                    if items.isEmpty {
                        emptyRow
                    }
                    bookmarkRows(items, track: track)
                } else {
                    emptyRow
                }
            }
            .id(refresh)
            .navigationTitle("Закладки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Показывать", selection: $showAll) {
                        Text("Этот трек").tag(false)
                        Text("Все").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .alert(
                "Заметка",
                isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })
            ) {
                TextField("Текст заметки", text: $noteText)
                Button("Сохранить") {
                    if let editing {
                        container.library.updateBookmark(editing, note: noteText)
                        refresh += 1
                    }
                    editing = nil
                }
                Button("Отмена", role: .cancel) {
                    editing = nil
                }
            }
        }
    }

    private var emptyRow: some View {
        Text("Закладок пока нет. Нажмите значок закладки на панели плеера, чтобы отметить текущее место.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func bookmarkRows(_ items: [Bookmark], track: TrackRecord) -> some View {
        ForEach(items, id: \.uid) { bookmark in
            Button {
                playback.playTrack(uid: track.uid, at: bookmark.time)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Text(TimeText.format(bookmark.time))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(palette.accent)
                    Text(bookmark.note.isEmpty ? "Без заметки" : bookmark.note)
                        .foregroundStyle(bookmark.note.isEmpty ? .secondary : .primary)
                        .lineLimit(2)
                    Spacer()
                }
            }
            .swipeActions {
                Button(role: .destructive) {
                    container.library.deleteBookmark(bookmark)
                    refresh += 1
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
            .contextMenu {
                Button {
                    noteText = bookmark.note
                    editing = bookmark
                } label: {
                    Label("Изменить заметку", systemImage: "pencil")
                }
            }
        }
    }
}

/// Список глав текущей книги; нажатие — переход к главе.
struct ChaptersView: View {
    let playback: PlaybackController

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(playback.chapters) { chapter in
                Button {
                    playback.goToChapter(chapter)
                    dismiss()
                } label: {
                    HStack {
                        Text(chapter.title)
                            .foregroundStyle(chapter.id == playback.currentChapterIndex ? palette.accent : palette.text)
                            .fontWeight(chapter.id == playback.currentChapterIndex ? .bold : .regular)
                        Spacer()
                        Text(TimeText.format(chapter.start))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Главы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
