import SwiftUI

// MARK: - Звук и воспроизведение

struct SoundSettingsView: View {
    let container: AppContainer

    @AppStorage(SettingsKeys.startMode) private var startMode = "continue"
    @AppStorage(SettingsKeys.skipInterval) private var skipInterval = 15
    @AppStorage(SettingsKeys.lockScreenMode) private var lockScreenMode = "skip"
    @AppStorage(SettingsKeys.normalize) private var normalize = true
    @AppStorage(SettingsKeys.fadeEnd) private var fadeEnd = false
    @AppStorage(SettingsKeys.fadeEndSeconds) private var fadeEndSeconds = 5
    @AppStorage(SettingsKeys.haptics) private var haptics = false
    @AppStorage(SettingsKeys.rememberAudiobookPosition) private var rememberBooks = true
    @AppStorage(SettingsKeys.audiobookThresholdMinutes) private var bookThreshold = 20
    @AppStorage(SettingsKeys.resumeRewindSeconds) private var rewindSeconds = 3

    @State private var customSkip = ""
    @State private var showEqualizer = false
    @State private var showSleepTimer = false
    @Environment(\.palette) private var palette

    private let skipPresets = [5, 10, 15, 30]

    var body: some View {
        List {
            Section {
                Picker("При запуске", selection: $startMode.withHaptic()) {
                    Text("Продолжить с места остановки").tag("continue")
                    Text("Ничего не воспроизводить").tag("idle")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("При запуске приложения")
            } footer: {
                Text(startMode == "idle"
                     ? "Плеер откроется на последнем плейлисте и треке, но играть не начнёт."
                     : "Музыка продолжит играть с той секунды, где остановилась при закрытии.")
            }

            Section {
                Picker("Шаг перемотки", selection: skipChoice.withHaptic()) {
                    ForEach(skipPresets, id: \.self) { value in
                        Text("\(value) с").tag(value)
                    }
                    Text("Своё").tag(0)
                }
                .pickerStyle(.segmented)
                if !skipPresets.contains(skipInterval) {
                    HStack {
                        Text("Своё значение")
                        Spacer()
                        TextField("15", text: $customSkip)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .onSubmit(applyCustomSkip)
                            .onChange(of: customSkip) { _, _ in applyCustomSkip() }
                        Text("с (1–600)").foregroundStyle(.secondary)
                    }
                }
                Picker("Кнопки на экране блокировки", selection: $lockScreenMode.withHaptic()) {
                    Text("Перемотка ±\(skipInterval) с").tag("skip")
                    Text("Пред./след. трек").tag("tracks")
                }
            } header: {
                Text("Перемотка")
            } footer: {
                Text("iOS показывает на экране блокировки только три кнопки, поэтому одновременно либо перемотка, либо переход между треками. В самом приложении есть и то, и другое.")
            }
            .onChange(of: skipInterval) { _, _ in container.playback.applyLockScreenSettings() }
            .onChange(of: lockScreenMode) { _, _ in container.playback.applyLockScreenSettings() }

            Section("Звук") {
                Toggle("Выравнивание громкости", isOn: $normalize.withHaptic())
                    .onChange(of: normalize) { _, _ in container.playback.applyNormalizationSetting() }
                Toggle("Плавное затухание в конце трека", isOn: $fadeEnd.withHaptic())
                if fadeEnd {
                    Stepper("Длительность затухания: \(fadeEndSeconds) с", value: $fadeEndSeconds.withHaptic(), in: 1...10)
                }
                Toggle(isOn: $haptics) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Вибрация (тактильный отклик)")
                        Text("Play/Пауза и любые действия в меню")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: haptics) { _, _ in Haptics.select() }
                Button {
                    Haptics.select()
                    showEqualizer = true
                } label: {
                    LabeledContent("Эквалайзер", value: container.equalizer.isEnabled ? container.equalizer.presetName : "выкл")
                }
                .foregroundStyle(.primary)
                Button {
                    Haptics.select()
                    showSleepTimer = true
                } label: {
                    LabeledContent("Таймер сна", value: container.playback.sleepTimer.isActive ? "вкл" : "выкл")
                }
                .foregroundStyle(.primary)
            }

            Section("Аудиокниги") {
                Toggle("Запоминать позицию", isOn: $rememberBooks.withHaptic())
                Picker("Аудиокнига — файлы от", selection: $bookThreshold.withHaptic()) {
                    Text("10 мин").tag(10)
                    Text("20 мин").tag(20)
                    Text("30 мин").tag(30)
                    Text("60 мин").tag(60)
                }
                Picker("Откат при возобновлении", selection: $rewindSeconds.withHaptic()) {
                    Text("0 с").tag(0)
                    Text("3 с").tag(3)
                    Text("5 с").tag(5)
                    Text("10 с").tag(10)
                }
            }
        }
        .navigationTitle("Звук и воспроизведение")
        .onAppear {
            if !skipPresets.contains(skipInterval) {
                customSkip = String(skipInterval)
            }
        }
        .sheet(isPresented: $showEqualizer) {
            EqualizerView(equalizer: container.equalizer)
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerView(timer: container.playback.sleepTimer)
                .environment(\.palette, palette)
        }
    }

    /// 0 в выборе = «Своё».
    private var skipChoice: Binding<Int> {
        Binding(
            get: { skipPresets.contains(skipInterval) ? skipInterval : 0 },
            set: { value in
                if value == 0 {
                    customSkip = String(skipInterval)
                    if skipPresets.contains(skipInterval) {
                        skipInterval = 20
                        customSkip = "20"
                    }
                } else {
                    skipInterval = value
                }
            }
        )
    }

    private func applyCustomSkip() {
        guard let value = Int(customSkip) else { return }
        skipInterval = min(max(value, 1), 600)
    }
}

// MARK: - Библиотека и плейлисты

struct LibrarySettingsView: View {
    let container: AppContainer

    @AppStorage(SettingsKeys.showPlayCount) private var showPlayCount = true
    @AppStorage(SettingsKeys.showHitTab) private var showHitTab = true
    @AppStorage(SettingsKeys.showSuperTab) private var showSuperTab = true
    @AppStorage(SettingsKeys.showHeart) private var showHeart = true
    @AppStorage(SettingsKeys.allowDuplicates) private var allowDuplicates = true
    @AppStorage(SettingsKeys.insertAtStart) private var insertAtStart = false
    @AppStorage(SettingsKeys.rememberFolder) private var rememberFolder = true
    @AppStorage(SettingsKeys.searchEngine) private var searchEngine = "google"

    var body: some View {
        List {
            Section("Список треков") {
                Toggle("Счётчик прослушиваний", isOn: $showPlayCount.withHaptic())
                Toggle("Показывать вкладку ★ (хит-парад)", isOn: $showHitTab.withHaptic())
                Toggle("Показывать вкладку ♥ «Супер!»", isOn: $showSuperTab.withHaptic())
                Toggle("Сердечко «Супер!» в строках", isOn: $showHeart.withHaptic())
            }

            Section {
                Toggle("Разрешать дубликаты", isOn: $allowDuplicates.withHaptic())
            } footer: {
                Text("Если выключено — при добавлении такой же композиции появится уведомление с номером строки, и повтор не добавится.")
            }

            Section("Добавление файлов") {
                Picker("Куда добавлять новые", selection: $insertAtStart.withHaptic()) {
                    Text("В конец").tag(false)
                    Text("В начало").tag(true)
                }
                Toggle("Запоминать последнюю папку", isOn: $rememberFolder.withHaptic())
            }

            Section("Найти в интернете") {
                Picker("Поисковик", selection: $searchEngine.withHaptic()) {
                    Text("Google").tag("google")
                    Text("Яндекс").tag("yandex")
                    Text("DuckDuckGo").tag("duckduckgo")
                }
            }

            Section("Мои плейлисты") {
                NavigationLink("Порядок, переименование, удаление") {
                    PlaylistsManagerView(lists: container.lists)
                        .onAppear { Haptics.select() }
                }
            }
        }
        .navigationTitle("Библиотека и плейлисты")
    }
}

/// Плейлисты: перетаскивание за ≡, переименование, удаление, «По алфавиту».
/// ★ и ♥ нельзя переименовать, удалить или переместить.
struct PlaylistsManagerView: View {
    let lists: QueueAndPlaylistManager

    @State private var toRename: Playlist?
    @State private var renameText = ""
    @State private var toDelete: Playlist?

    var body: some View {
        List {
            Section {
                lockedRow("★  хит-парад")
                lockedRow("♥  Супер!")
            }
            Section {
                ForEach(lists.playlists, id: \.uid) { playlist in
                    HStack {
                        Text(playlist.name)
                        Spacer()
                        Button {
                            Haptics.select()
                            renameText = playlist.name
                            toRename = playlist
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Переименовать «\(playlist.name)»")
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            toDelete = playlist
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
                .onMove { offsets, destination in
                    Haptics.select()
                    lists.movePlaylists(fromOffsets: offsets, toOffset: destination)
                }
                if lists.playlists.isEmpty {
                    Text("Плейлистов пока нет — создайте их кнопкой «+» на главном экране.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Порядок меняется перетаскиванием за ≡. Так же — долгим нажатием на вкладку на главном экране.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Мои плейлисты")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("А–Я") {
                    Haptics.tap()
                    lists.sortPlaylistsAlphabetically()
                }
            }
        }
        .alert(
            "Переименовать плейлист",
            isPresented: Binding(get: { toRename != nil }, set: { if !$0 { toRename = nil } })
        ) {
            TextField("Название", text: $renameText)
            Button("Сохранить") {
                if let toRename { lists.renamePlaylist(toRename, to: renameText) }
                toRename = nil
            }
            Button("Отмена", role: .cancel) { toRename = nil }
        }
        .alert(
            "Удалить плейлист?",
            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
            presenting: toDelete
        ) { playlist in
            Button("Удалить", role: .destructive) {
                lists.deletePlaylist(playlist)
                toDelete = nil
            }
            Button("Отмена", role: .cancel) { toDelete = nil }
        } message: { playlist in
            Text("Плейлист «\(playlist.name)» будет удалён. Файлы останутся на устройстве.")
        }
    }

    private func lockedRow(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("автоматический")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .moveDisabled(true)
        .deleteDisabled(true)
    }
}
