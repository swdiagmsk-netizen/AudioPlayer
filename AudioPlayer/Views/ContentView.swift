import SwiftUI
import UniformTypeIdentifiers

/// Временный экран этапа 1: список библиотеки, импорт, простое воспроизведение.
/// Полноценный главный экран появится на этапе 4.
struct ContentView: View {
    let container: AppContainer

    @State private var showImporter = false
    @State private var showLog = false
    @State private var reportText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                nowPlaying
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
                "Импорт",
                isPresented: Binding(
                    get: { reportText != nil },
                    set: { if !$0 { reportText = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(reportText ?? "")
            }
        }
    }

    // MARK: - Части экрана

    private var nowPlaying: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(container.player.hasFile ? container.player.title : "Ничего не играет")
                    .font(.headline)
                    .lineLimit(1)
                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                container.player.togglePlayPause()
            } label: {
                Image(systemName: container.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
            }
            .disabled(!container.player.hasFile)
            .accessibilityLabel(container.player.isPlaying ? "Пауза" : "Играть")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var statusLine: String {
        let library = container.library
        if library.isBusy, !library.progressText.isEmpty { return library.progressText }
        if container.player.hasFile { return container.player.status }
        return "Треков в библиотеке: \(library.tracks.count)"
    }

    private var trackList: some View {
        let tracks = container.library.tracks
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
                            play(track)
                        } label: {
                            row(index: index, track: track)
                        }
                        .buttonStyle(.plain)
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
            Text(formatDuration(track.duration))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Действия

    private func play(_ track: TrackRecord) {
        if track.isProtected || !track.isPlayable {
            reportText = "Файл «\(track.fileName)» защищён (DRM) и не может быть воспроизведён в этом приложении."
            return
        }
        container.player.playFile(at: track.fileURL, title: track.displayTitle)
    }

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

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
