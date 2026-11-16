import SwiftUI

/// Меню файла (⚙ в строке): «Супер!», поделиться, поиск в интернете,
/// плейлисты, удаление с устройства.
struct FileActionsSheet: View {
    let track: TrackRecord
    let entry: PlaylistEntry?
    let rowNumber: Int?
    let onToggleSuper: () -> Void
    let onEditTags: () -> Void
    let onMail: () -> Void
    let onAddToPlaylist: () -> Void
    let onRemoveFromPlaylist: () -> Void
    let onDelete: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(palette.line)
            ScrollView {
                VStack(spacing: 0) {
                    actionRow(
                        icon: track.isSuper ? "heart.fill" : "heart",
                        iconColor: Palette.heart,
                        title: track.isSuper ? tr("Убрать из «Супер!»") : tr("Супер!")
                    ) {
                        onToggleSuper()
                    }

                    actionRow(icon: "pencil", iconColor: palette.text, title: tr("Изменить теги и имя файла")) {
                        dismiss()
                        onEditTags()
                    }

                    actionRow(icon: "envelope", iconColor: palette.text, title: tr("Отправить по почте"), subtitle: tr("Файл во вложении")) {
                        dismiss()
                        onMail()
                    }

                    ShareLink(item: track.fileURL) {
                        rowLabel(
                            icon: "square.and.arrow.up",
                            iconColor: palette.text,
                            title: tr("Поделиться файлом"),
                            subtitle: tr("AirDrop на другое устройство, мессенджеры и другое")
                        )
                    }
                    .buttonStyle(.plain)
                    separator

                    actionRow(
                        icon: "globe",
                        iconColor: palette.text,
                        title: tr("Найти в интернете"),
                        subtitle: tr("Поиск: «%@»", "\(searchQuery)")
                    ) {
                        if let url = AppSettings.searchURL(for: searchQuery) {
                            openURL(url)
                        }
                    }

                    actionRow(icon: "text.badge.plus", iconColor: palette.text, title: tr("Добавить в плейлист…")) {
                        dismiss()
                        onAddToPlaylist()
                    }

                    if entry != nil {
                        actionRow(icon: "minus.circle", iconColor: palette.text, title: tr("Убрать из этого плейлиста")) {
                            onRemoveFromPlaylist()
                            dismiss()
                        }
                    }

                    actionRow(icon: "trash", iconColor: Palette.danger, title: tr("Удалить с устройства…"), titleColor: Palette.danger) {
                        dismiss()
                        onDelete()
                    }
                }
            }
        }
        .background(palette.panel)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var searchQuery: String {
        [track.artist, track.displayTitle].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(rowNumber.map { String(format: "%02d", $0) } ?? "--")
                .font(.system(size: 18, design: .monospaced))
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.headline)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private var details: String {
        let artist = track.artist.isEmpty ? tr("Неизвестный исполнитель") : track.artist
        return "\(artist) · \(TimeText.format(track.duration)) · ▶ \(track.playCount)"
    }

    private var separator: some View {
        Rectangle().fill(palette.line).frame(height: 1).padding(.leading, 54)
    }

    private func actionRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        titleColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                Haptics.tap()
                action()
            } label: {
                rowLabel(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle, titleColor: titleColor)
            }
            .buttonStyle(.plain)
            separator
        }
    }

    private func rowLabel(icon: String, iconColor: Color, title: String, subtitle: String? = nil, titleColor: Color? = nil) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(titleColor ?? palette.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Выбор плейлиста для добавления треков (или создание нового).
struct AddToPlaylistSheet: View {
    let lists: QueueAndPlaylistManager
    let tracks: [TrackRecord]
    let onDone: (String) -> Void
    let onDuplicates: ([DuplicateInfo]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(tr("Новый плейлист"), text: $newName)
                        Button(tr("Создать")) {
                            if let playlist = lists.createPlaylist(named: newName) {
                                add(to: playlist)
                            }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section(tr("Мои плейлисты")) {
                    if lists.playlists.isEmpty {
                        Text(tr("Плейлистов пока нет"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lists.playlists, id: \.uid) { playlist in
                        Button(playlist.name) {
                            add(to: playlist)
                        }
                    }
                }
            }
            .navigationTitle(tracks.count == 1 ? tr("Добавить трек") : tr("Добавить треки: %@", "\(tracks.count)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Отмена")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add(to playlist: Playlist) {
        Haptics.tap()
        let duplicates = lists.add(tracks, to: playlist)
        let added = tracks.count - duplicates.count
        if added > 0 {
            onDone(tr("Добавлено в «%@»: %@", "\(playlist.name)", "\(added)"))
        }
        dismiss()
        if !duplicates.isEmpty {
            onDuplicates(duplicates)
        }
    }
}
