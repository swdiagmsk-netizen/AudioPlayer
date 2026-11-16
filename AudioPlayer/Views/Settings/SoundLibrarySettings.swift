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
                Picker(tr("При запуске"), selection: $startMode.withHaptic()) {
                    Text(tr("Продолжить с места остановки")).tag("continue")
                    Text(tr("Ничего не воспроизводить")).tag("idle")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text(tr("При запуске приложения"))
            } footer: {
                Text(startMode == "idle"
                     ? tr("Плеер откроется на последнем плейлисте и треке, но играть не начнёт.")
                     : tr("Музыка продолжит играть с той секунды, где остановилась при закрытии."))
            }

            Section {
                Picker(tr("Шаг перемотки"), selection: skipChoice.withHaptic()) {
                    ForEach(skipPresets, id: \.self) { value in
                        Text(tr("%@ с", "\(value)")).tag(value)
                    }
                    Text(tr("Своё")).tag(0)
                }
                .pickerStyle(.segmented)
                if !skipPresets.contains(skipInterval) {
                    HStack {
                        Text(tr("Своё значение"))
                        Spacer()
                        TextField("15", text: $customSkip)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .onSubmit(applyCustomSkip)
                            .onChange(of: customSkip) { _, _ in applyCustomSkip() }
                        Text(tr("с (1–600)")).foregroundStyle(.secondary)
                    }
                }
                Picker(tr("Кнопки на экране блокировки"), selection: $lockScreenMode.withHaptic()) {
                    Text(tr("Перемотка ±%@ с", "\(skipInterval)")).tag("skip")
                    Text(tr("Пред./след. трек")).tag("tracks")
                }
            } header: {
                Text(tr("Перемотка"))
            } footer: {
                Text(tr("iOS показывает на экране блокировки только три кнопки, поэтому одновременно либо перемотка, либо переход между треками. В самом приложении есть и то, и другое."))
            }
            .onChange(of: skipInterval) { _, _ in container.playback.applyLockScreenSettings() }
            .onChange(of: lockScreenMode) { _, _ in container.playback.applyLockScreenSettings() }

            Section(tr("Звук")) {
                Toggle(tr("Выравнивание громкости"), isOn: $normalize.withHaptic())
                    .onChange(of: normalize) { _, _ in container.playback.applyNormalizationSetting() }
                Toggle(tr("Плавное затухание в конце трека"), isOn: $fadeEnd.withHaptic())
                if fadeEnd {
                    Stepper(tr("Длительность затухания: %@ с", "\(fadeEndSeconds)"), value: $fadeEndSeconds.withHaptic(), in: 1...10)
                }
                Toggle(isOn: $haptics) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Вибрация (тактильный отклик)"))
                        Text(tr("Play/Пауза и любые действия в меню"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: haptics) { _, _ in Haptics.select() }
                Button {
                    Haptics.select()
                    showEqualizer = true
                } label: {
                    LabeledContent(tr("Эквалайзер"), value: container.equalizer.isEnabled ? tr(container.equalizer.presetName) : tr("выкл"))
                }
                .foregroundStyle(.primary)
                Button {
                    Haptics.select()
                    showSleepTimer = true
                } label: {
                    LabeledContent(tr("Таймер сна"), value: container.playback.sleepTimer.isActive ? tr("вкл") : tr("выкл"))
                }
                .foregroundStyle(.primary)
            }

            Section(tr("Аудиокниги")) {
                Toggle(tr("Запоминать позицию"), isOn: $rememberBooks.withHaptic())
                Picker(tr("Аудиокнига — файлы от"), selection: $bookThreshold.withHaptic()) {
                    Text(tr("10 мин")).tag(10)
                    Text(tr("20 мин")).tag(20)
                    Text(tr("30 мин")).tag(30)
                    Text(tr("60 мин")).tag(60)
                }
                Picker(tr("Откат при возобновлении"), selection: $rewindSeconds.withHaptic()) {
                    Text(tr("0 с")).tag(0)
                    Text(tr("3 с")).tag(3)
                    Text(tr("5 с")).tag(5)
                    Text(tr("10 с")).tag(10)
                }
            }
        }
        .navigationTitle(tr("Звук и воспроизведение"))
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
            Section(tr("Список треков")) {
                Toggle(tr("Счётчик прослушиваний"), isOn: $showPlayCount.withHaptic())
                Toggle(tr("Показывать вкладку ★ (хит-парад)"), isOn: $showHitTab.withHaptic())
                Toggle(tr("Показывать вкладку ♥ «Супер!»"), isOn: $showSuperTab.withHaptic())
                Toggle(tr("Сердечко «Супер!» в строках"), isOn: $showHeart.withHaptic())
            }

            Section {
                Toggle(tr("Разрешать дубликаты"), isOn: $allowDuplicates.withHaptic())
                NavigationLink {
                    DuplicatesView(container: container)
                        .onAppear { Haptics.select() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Найти и убрать дубликаты"))
                        Text(tr("Только из плейлистов. С iPhone — лишь после подтверждения"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(tr("Если выключено — при добавлении такой же композиции появится уведомление с номером строки, и повтор не добавится."))
            }

            Section(tr("Добавление файлов")) {
                Picker(tr("Куда добавлять новые"), selection: $insertAtStart.withHaptic()) {
                    Text(tr("В конец")).tag(false)
                    Text(tr("В начало")).tag(true)
                }
                Toggle(tr("Запоминать последнюю папку"), isOn: $rememberFolder.withHaptic())
                NavigationLink(tr("Wi-Fi-импорт с компьютера")) {
                    WiFiTransferView(controller: container.wifi)
                        .onAppear { Haptics.select() }
                }
                NavigationLink {
                    RecognitionHistoryView(controller: container.recognition)
                        .onAppear { Haptics.select() }
                } label: {
                    HStack {
                        Text(tr("Распознанные песни"))
                        Spacer()
                        let waiting = container.recognition.store.pending.count
                        if waiting > 0 {
                            Text(tr("ждут сети: %@", "\(waiting)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(tr("Найти в интернете")) {
                Picker(tr("Поисковик"), selection: $searchEngine.withHaptic()) {
                    Text("Google").tag("google")
                    Text(tr("Яндекс")).tag("yandex")
                    Text("DuckDuckGo").tag("duckduckgo")
                }
            }

            Section(tr("Мои плейлисты")) {
                NavigationLink(tr("Порядок, переименование, удаление")) {
                    PlaylistsManagerView(lists: container.lists)
                        .onAppear { Haptics.select() }
                }
            }
        }
        .navigationTitle(tr("Библиотека и плейлисты"))
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
                lockedRow(tr("★  хит-парад"))
                lockedRow(tr("♥  Супер!"))
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
                        .accessibilityLabel(tr("Переименовать «%@»", "\(playlist.name)"))
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            toDelete = playlist
                        } label: {
                            Label(tr("Удалить"), systemImage: "trash")
                        }
                    }
                }
                .onMove { offsets, destination in
                    Haptics.select()
                    lists.movePlaylists(fromOffsets: offsets, toOffset: destination)
                }
                if lists.playlists.isEmpty {
                    Text(tr("Плейлистов пока нет — создайте их кнопкой «+» на главном экране."))
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(tr("Порядок меняется перетаскиванием за ≡. Так же — долгим нажатием на вкладку на главном экране."))
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(tr("Мои плейлисты"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(tr("А–Я")) {
                    Haptics.tap()
                    lists.sortPlaylistsAlphabetically()
                }
            }
        }
        .alert(
            tr("Переименовать плейлист"),
            isPresented: Binding(get: { toRename != nil }, set: { if !$0 { toRename = nil } })
        ) {
            TextField(tr("Название"), text: $renameText)
            Button(tr("Сохранить")) {
                if let toRename { lists.renamePlaylist(toRename, to: renameText) }
                toRename = nil
            }
            Button(tr("Отмена"), role: .cancel) { toRename = nil }
        }
        .alert(
            tr("Удалить плейлист?"),
            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
            presenting: toDelete
        ) { playlist in
            Button(tr("Удалить"), role: .destructive) {
                lists.deletePlaylist(playlist)
                toDelete = nil
            }
            Button(tr("Отмена"), role: .cancel) { toDelete = nil }
        } message: { playlist in
            Text(tr("Плейлист «%@» будет удалён. Файлы останутся на устройстве.", "\(playlist.name)"))
        }
    }

    private func lockedRow(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(tr("автоматический"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .moveDisabled(true)
        .deleteDisabled(true)
    }
}
