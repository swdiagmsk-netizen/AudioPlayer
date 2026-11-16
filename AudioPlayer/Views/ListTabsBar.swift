import SwiftUI

/// Горизонтальные вкладки: ★, ♥, «Все треки», «Папки», плейлисты, «+».
/// Вкладки плейлистов перетаскиваются; долгое нажатие — меню.
struct ListTabsBar: View {
    @Binding var selected: ListID
    let playlists: [Playlist]
    let currentFolder: String
    let onCreate: () -> Void
    let onRename: (Playlist) -> Void
    let onDelete: (Playlist) -> Void
    /// Перенести плейлист `uid` на место плейлиста `target`.
    let onMove: (UUID, UUID) -> Void

    @Environment(\.palette) private var palette
    @AppStorage(SettingsKeys.showHitTab) private var showHitTab = true
    @AppStorage(SettingsKeys.showSuperTab) private var showSuperTab = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if showHitTab {
                        chip("★", accessibility: "Твой хит-парад", isOn: selected == .hitParade) {
                            selected = .hitParade
                        }
                        .id("hit")
                    }
                    if showSuperTab {
                        chip("♥", accessibility: "Супер!", isOn: selected == .superList) {
                            selected = .superList
                        }
                        .id("super")
                    }
                    chip("Все треки", accessibility: "Все треки", isOn: selected == .all) {
                        selected = .all
                    }
                    .id("all")
                    chip("Папки", accessibility: "Папки", isOn: isFolderSelected) {
                        selected = .folder(currentFolder)
                    }
                    .id("folders")

                    ForEach(playlists, id: \.uid) { playlist in
                        chip(playlist.name, accessibility: playlist.name, isOn: selected == .playlist(playlist.uid)) {
                            selected = .playlist(playlist.uid)
                        }
                        .id(playlist.uid.uuidString)
                        .contextMenu {
                            Button {
                                onRename(playlist)
                            } label: {
                                Label("Переименовать", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                onDelete(playlist)
                            } label: {
                                Label("Удалить плейлист", systemImage: "trash")
                            }
                        }
                        .draggable(playlist.uid.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let first = items.first, let uid = UUID(uuidString: first), uid != playlist.uid else {
                                return false
                            }
                            onMove(uid, playlist.uid)
                            return true
                        }
                    }

                    Button(action: onCreate) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.text)
                            .frame(width: 44, height: 34)
                            .background(Capsule().fill(palette.button))
                            .overlay(Capsule().stroke(palette.line, lineWidth: 1))
                    }
                    .accessibilityLabel("Новый плейлист")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onAppear {
                proxy.scrollTo(scrollID, anchor: .center)
            }
        }
    }

    private var isFolderSelected: Bool {
        if case .folder = selected { return true }
        return false
    }

    private var scrollID: String {
        switch selected {
        case .hitParade: return "hit"
        case .superList: return "super"
        case .all: return "all"
        case .folder: return "folders"
        case .playlist(let uid): return uid.uuidString
        }
    }

    private func chip(_ title: String, accessibility: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(isOn ? palette.onAccent : palette.text)
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 34)
                .background(Capsule().fill(isOn ? palette.accent : palette.button))
                .overlay(Capsule().stroke(isOn ? palette.accent : palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
