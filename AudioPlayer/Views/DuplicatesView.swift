import SwiftUI

/// «Найти и убрать дубликаты»: группы одинаковых композиций.
/// Повторы убираются только из плейлистов; лишние файлы с устройства —
/// отдельной кнопкой и только после подтверждения.
struct DuplicatesView: View {
    let container: AppContainer

    @State private var groups: [[TrackRecord]] = []
    /// Какой трек оставить в каждой группе.
    @State private var keepers: [UUID] = []
    @State private var result: String?
    @State private var confirmDelete = false

    var body: some View {
        List {
            if groups.isEmpty {
                Section {
                    Text(tr("Дубликатов не найдено."))
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text(tr("Дубликат — тот же файл по содержимому или совпадение исполнителя и названия при разнице длительности до 2 секунд. Отметьте, какой трек оставить."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(groups.indices, id: \.self) { index in
                    Section(tr("Группа %@", "\(index + 1)")) {
                        ForEach(groups[index], id: \.uid) { track in
                            Button {
                                Haptics.select()
                                keepers[index] = track.uid
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.displayTitle).foregroundStyle(.primary)
                                        Text("\(track.artist.isEmpty ? tr("Неизвестный исполнитель") : track.artist) · \(TimeText.format(track.duration)) · \(track.fileName)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: keepers[index] == track.uid ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .accessibilityAddTraits(keepers[index] == track.uid ? .isSelected : [])
                        }
                    }
                }
                Section {
                    Button(tr("Убрать повторы из плейлистов")) {
                        Haptics.tap()
                        let removed = container.lists.removeDuplicatesFromPlaylists(groups: groups, keepers: keepers)
                        result = removed > 0 ? tr("Убрано строк из плейлистов: %@. Файлы остались на устройстве.", "\(removed)") : tr("В плейлистах повторов нет.")
                    }
                    Button(tr("Удалить лишние файлы с устройства…"), role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
        }
        .navigationTitle(tr("Дубликаты"))
        .onAppear(perform: reload)
        .alert(tr("Готово"), isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(result ?? "")
        }
        .alert(tr("Удалить лишние файлы?"), isPresented: $confirmDelete) {
            Button(tr("Удалить"), role: .destructive) {
                deleteExtras()
            }
            Button(tr("Отмена"), role: .cancel) {}
        } message: {
            Text(deleteList)
        }
    }

    private var extras: [TrackRecord] {
        groups.enumerated().flatMap { index, group in
            group.filter { $0.uid != keepers[index] }
        }
    }

    private var deleteList: String {
        let names = extras.prefix(8).map { "• " + $0.fileName }
        let more = extras.count > 8 ? tr("\n…и ещё %@", "\(extras.count - 8)") : ""
        return tr("С iPhone будут удалены файлы (%@):\n", "\(extras.count)") + names.joined(separator: "\n") + more + tr("\n\nОтменить нельзя.")
    }

    private func reload() {
        groups = container.library.duplicateGroups()
        // По умолчанию оставляем самый прослушиваемый трек группы
        keepers = groups.map { group in
            (group.max { $0.playCount < $1.playCount } ?? group[0]).uid
        }
    }

    private func deleteExtras() {
        let tracks = extras
        var deleted = 0
        for track in tracks {
            container.playback.handleDeleted(uid: track.uid)
            if container.library.deleteFromDevice(track) {
                deleted += 1
            }
        }
        result = tr("Удалено файлов: %@ из %@.", "\(deleted)", "\(tracks.count)")
        reload()
    }
}
