import SwiftUI
import UniformTypeIdentifiers

/// Временный экран (этапы 1–3): список библиотеки, импорт, управление воспроизведением.
/// Согласованный дизайн главного экрана появится на этапе 4.
struct ContentView: View {
    let container: AppContainer

    @State private var showImporter = false
    @State private var showLog = false
    @State private var reportText: String?
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    @AppStorage(SettingsKeys.skipInterval) private var skipInterval: Int = 15

    private var playback: PlaybackController { container.playback }
    private var engine: AudioEngineManager { container.playback.engine }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                playerPanel
                Divider()
                trackList
            }
            .navigationTitle("PlayMyDisk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLog = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel("Журнал отладки")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Добавить файлы")
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: AudioFormats.importTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        let report = await container.library.importFiles(urls)
                        reportText = describe(report)
                    }
                case .failure(let error):
                    reportText = "Не удалось выбрать файлы: \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $showLog) {
                DebugLogView()
            }
            .alert(
                "PlayMyDisk",
                isPresented: Binding(
                    get: { reportText != nil || playback.message != nil },
                    set: { shown in
                        if !shown {
                            reportText = nil
                            playback.message = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(reportText ?? playback.message ?? "")
            }
        }
    }

    // MARK: - Панель плеера

    private var playerPanel: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(playback.currentTrack?.displayTitle ?? "Ничего не играет")
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { isDragging ? dragValue : engine.currentTime },
                        set: { dragValue = $0 }
                    ),
                    in: 0...max(engine.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            dragValue = engine.currentTime
                            isDragging = true
                        } else {
                            playback.seek(to: dragValue)
                            isDragging = false
                        }
                    }
                )
                .disabled(!engine.isLoaded)
                HStack {
                    Text(formatTime(isDragging ? dragValue : engine.currentTime))
                    Spacer()
                    Text(formatTime(engine.duration))
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                Button { playback.previous() } label: {
                    Image(systemName: "backward.end.fill").font(.title2)
                }
                .accessibilityLabel("Предыдущий трек")

                Button { playback.skipBackward() } label: {
                    Image(systemName: "gobackward").font(.title2)
                        .overlay(Text("\(skipInterval)").font(.system(size: 9, weight: .bold)).offset(y: 1))
                }
                .accessibilityLabel("Назад на \(skipInterval) секунд")

                Button { playback.togglePlayPause() } label: {
                    Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                }
                .accessibilityLabel(engine.isPlaying ? "Пауза" : "Играть")

                Button { playback.skipForward() } label: {
                    Image(systemName: "goforward").font(.title2)
                        .overlay(Text("\(skipInterval)").font(.system(size: 9, weight: .bold)).offset(y: 1))
                }
                .accessibilityLabel("Вперёд на \(skipInterval) секунд")

                Button { playback.next() } label: {
                    Image(systemName: "forward.end.fill").font(.title2)
                }
                .accessibilityLabel("Следующий трек")
            }
            .disabled(playback.currentTrack == nil)

            HStack(spacing: 28) {
                Button { playback.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(playback.shuffleOn ? Color.orange : Color.secondary)
                }
                .accessibilityLabel("Честный рандом")

                Button { playback.cycleRepeat() } label: {
                    Image(systemName: playback.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundStyle(playback.repeatMode == .off ? Color.secondary : Color.orange)
                }
                .accessibilityLabel("Повтор")

                Button { container.lists.shuffleList(.all) } label: {
                    Image(systemName: "arrow.triangle.swap")
                }
                .accessibilityLabel("Перемешать список")

                Button { container.lists.sortAlphabetically(.all) } label: {
                    Image(systemName: "textformat.abc")
                }
                .accessibilityLabel("По алфавиту")
            }
            .font(.title3)

            Menu {
                ForEach(PlaybackSpeed.all, id: \.self) { rate in
                    Button(PlaybackSpeed.label(rate)) {
                        playback.setRate(rate)
                    }
                }
            } label: {
                Text(PlaybackSpeed.label(engine.rate))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(.secondary.opacity(0.5)))
            } primaryAction: {
                playback.setRate(PlaybackSpeed.next(after: engine.rate))
            }
            .accessibilityLabel("Скорость воспроизведения")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        let library = container.library
        if library.isBusy, !library.progressText.isEmpty { return library.progressText }
        if let track = playback.currentTrack {
            return track.artist.isEmpty ? "Неизвестный исполнитель" : track.artist
        }
        return "Треков в библиотеке: \(library.tracks.count)"
    }

    // MARK: - Список

    private var trackList: some View {
        let tracks = container.lists.tracks(for: .all)
        return Group {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "Библиотека пуста",
                    systemImage: "music.note.list",
                    description: Text("Нажмите + вверху, чтобы добавить музыку")
                )
            } else {
                List {
                    ForEach(Array(tracks.enumerated()), id: \.element.uid) { index, track in
                        Button {
                            playback.play(items: tracks.map(\.uid), startUID: track.uid, contextKey: ListID.all.key)
                        } label: {
                            row(index: index, track: track)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            track.uid == playback.currentTrack?.uid ? Color.orange.opacity(0.15) : Color.clear
                        )
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await container.library.rescan()
                }
            }
        }
    }

    private func row(index: Int, track: TrackRecord) -> some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", index + 1))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .lineLimit(1)
                Text(track.artist.isEmpty ? "Неизвестный исполнитель" : track.artist)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if track.isProtected {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Защищённый файл")
            }
            if track.playCount > 0 {
                Text("▶ \(track.playCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(formatTime(track.duration))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Вспомогательное

    private func describe(_ report: ImportReport) -> String? {
        if report.isEmpty { return nil }
        var lines: [String] = []
        lines.append("Добавлено: \(report.added.count)")
        if !report.skipped.isEmpty {
            lines.append("Пропущено (формат не поддерживается): \(report.skipped.count)")
        }
        if !report.failed.isEmpty {
            lines.append("Ошибки: \(report.failed.count)")
            lines.append(contentsOf: report.failed.prefix(5))
        }
        return lines.joined(separator: "\n")
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
