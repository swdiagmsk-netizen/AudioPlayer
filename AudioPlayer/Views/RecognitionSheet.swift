import SwiftUI
import UIKit

/// Экран распознавания: «Слушаю…», результат, «не найдено», «нет связи» или запасной вариант.
struct RecognitionSheet: View {
    let controller: RecognitionController

    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        VStack(spacing: 18) {
            content
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(palette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .idle:
            EmptyView()

        case .listening(let since):
            Image(systemName: RecognizeIcon.name)
                .font(.system(size: 64))
                .foregroundStyle(palette.accent)
                .symbolEffect(.pulse, options: .repeating)
                .padding(.top, 12)
            Text("Слушаю…")
                .font(.title2.bold())
                .foregroundStyle(palette.text)
            TimelineView(.periodic(from: since, by: 1)) { context in
                let seconds = max(0, Int(context.date.timeIntervalSince(since)))
                Text(String(format: "%d:%02d из 1:00", seconds / 60, seconds % 60))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
            }
            Text("Поднесите iPhone ближе к источнику звука.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.secondaryText)
            closeButton("Отмена")

        case .found(let song):
            AsyncImage(url: song.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(palette.secondaryText)
            }
            .frame(width: 160, height: 160)
            .background(palette.secondaryText.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(song.displayLine)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.text)
                .onTapGesture { copy(song) }
            actionButton(copied ? "Скопировано" : "Копировать «Исполнитель - Название»",
                         systemImage: copied ? "checkmark" : "doc.on.doc") {
                copy(song)
            }
            actionButton("Найти в интернете", systemImage: "magnifyingglass") {
                if let url = AppSettings.searchURL(for: song.displayLine) {
                    openURL(url)
                }
            }
            closeButton("Закрыть")

        case .notFound(let saved):
            Image(systemName: "questionmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 12)
            Text("За минуту песня не нашлась")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.text)
            hint(saved
                 ? "Фрагмент сохранён — попробую распознать ещё раз позже, при стабильной сети. Результат появится в «Настройки → Библиотека → Распознанные песни»."
                 : "Попробуйте ещё раз, когда музыка звучит громче и без помех.")
            actionButton("Ещё раз", systemImage: "arrow.clockwise") {
                copied = false
                controller.retry()
            }
            closeButton("Закрыть")

        case .offline(let saved):
            Image(systemName: "wifi.slash")
                .font(.system(size: 52))
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 12)
            Text("Нет связи")
                .font(.title3.bold())
                .foregroundStyle(palette.text)
            hint(saved
                 ? "Фрагмент записан. Распознаю автоматически, когда появится стабильная сотовая сеть или Wi-Fi, и покажу результат."
                 : "Не удалось сохранить фрагмент. Попробуйте ещё раз, когда появится связь.")
            actionButton("Ещё раз", systemImage: "arrow.clockwise") {
                controller.retry()
            }
            closeButton("Закрыть")

        case .micDenied:
            Image(systemName: "mic.slash")
                .font(.system(size: 56))
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 12)
            Text("Нет доступа к микрофону")
                .font(.title3.bold())
                .foregroundStyle(palette.text)
            hint("Разрешите доступ в Настройках iPhone → PlayMyDisk → Микрофон.")
            actionButton("Открыть Настройки", systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            closeButton("Закрыть")

        case .unavailable(let openedShazam):
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 52))
                .foregroundStyle(palette.accent)
                .padding(.top, 12)
            Text("Распознавание в плеере недоступно")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.text)
            hint(openedShazam
                 ? "Открыл приложение Shazam. Когда вернётесь — нажмите «Закрыть», и музыка продолжит играть."
                 : "Используйте «Распознавание музыки» в Пункте управления. Если кнопки там нет: Настройки iPhone → Пункт управления → добавьте «Распознавание музыки».")
            Text("Подробности — в Журнале отладки.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
            closeButton("Закрыть")
        }
    }

    private func copy(_ song: RecognizedSong) {
        UIPasteboard.general.string = song.displayLine
        Haptics.select()
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(palette.secondaryText)
    }

    private func actionButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(palette.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(palette.text)
        }
        .buttonStyle(PressDarkenStyle())
    }

    private func closeButton(_ title: LocalizedStringKey) -> some View {
        Button {
            Haptics.tap()
            copied = false
            controller.close()
        } label: {
            Text(title)
                .font(.body)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(palette.secondaryText)
        }
        .buttonStyle(PressDarkenStyle())
    }
}

/// Значок кнопки «Распознать»: логотип Shazam из SF Symbols, если он есть в системе.
enum RecognizeIcon {
    static let name: String = UIImage(systemName: "shazam.logo") != nil ? "shazam.logo" : "waveform.and.magnifyingglass"
}

/// История распознаваний: найденные (нажатие — копировать), ожидающие сети и не найденные.
struct RecognitionHistoryView: View {
    let controller: RecognitionController

    @Environment(\.palette) private var palette
    @State private var copiedID: UUID?
    @State private var isRetrying = false

    private var store: RecognitionStore { controller.store }

    var body: some View {
        List {
            let pending = store.entries.filter { $0.status == .pending }
            let found = store.entries.filter { $0.status == .found }
            let notFound = store.entries.filter { $0.status == .notFound }

            if store.entries.isEmpty {
                Text("Пока пусто. Нажмите кнопку распознавания на главном экране.")
                    .foregroundStyle(.secondary)
            }

            if !pending.isEmpty {
                Section {
                    ForEach(pending) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Фрагмент от \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                            Text("Попыток: \(entry.attempts) из \(RecognitionStore.maxAttempts)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions { deleteButton(entry) }
                    }
                    Button {
                        Haptics.tap()
                        isRetrying = true
                        Task {
                            await controller.processPending()
                            isRetrying = false
                        }
                    } label: {
                        HStack {
                            Text("Повторить сейчас")
                            if isRetrying {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRetrying)
                } header: {
                    Text("Ждут стабильной сети")
                }
            }

            if !found.isEmpty {
                Section {
                    ForEach(found) { entry in
                        Button {
                            if let song = entry.song {
                                UIPasteboard.general.string = song.displayLine
                                Haptics.select()
                                copiedID = entry.id
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.song?.displayLine ?? "")
                                        .foregroundStyle(.primary)
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .swipeActions { deleteButton(entry) }
                    }
                } header: {
                    Text("Найдено")
                } footer: {
                    Text("Нажмите на строку, чтобы скопировать «Исполнитель - Название».")
                }
            }

            if !notFound.isEmpty {
                Section {
                    ForEach(notFound) { entry in
                        Text("Фрагмент от \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                            .swipeActions { deleteButton(entry) }
                    }
                } header: {
                    Text("Не найдено")
                }
            }

            if !found.isEmpty || !notFound.isEmpty {
                Section {
                    Button("Очистить историю", role: .destructive) {
                        Haptics.tap()
                        store.clearFinished()
                    }
                }
            }
        }
        .navigationTitle("Распознанные песни")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteButton(_ entry: RecognitionEntry) -> some View {
        Button(role: .destructive) {
            Haptics.tap()
            store.delete(entry.id)
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }
}
