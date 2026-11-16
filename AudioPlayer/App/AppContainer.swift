import Foundation
import SwiftData
import Observation

/// Общие объекты приложения: база данных, библиотека, воспроизведение.
/// Создаётся один раз при запуске.
@MainActor
@Observable
final class AppContainer {
    let modelContainer: ModelContainer
    let library: LibraryAndBookmarkManager
    let lists: QueueAndPlaylistManager
    let playback: PlaybackController
    let equalizer: EqualizerManager
    let wifi: WiFiTransferController
    let recognition: RecognitionController

    /// Первое сканирование и восстановление состояния уже выполнены.
    private(set) var didFinishLaunchTasks = false

    init() {
        let schema = Schema([
            TrackRecord.self,
            Playlist.self,
            PlaylistEntry.self,
            Bookmark.self,
            ListState.self,
            EQPreset.self
        ])
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            // База на диске не открылась — работаем в памяти, чтобы приложение хотя бы запустилось
            AppLogger.shared.log("db", "Не удалось открыть базу: \(error.localizedDescription). Временная база в памяти.")
            do {
                container = try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
            } catch {
                fatalError("Не удалось создать базу данных: \(error)")
            }
        }
        modelContainer = container
        library = LibraryAndBookmarkManager(context: container.mainContext)
        lists = QueueAndPlaylistManager(context: container.mainContext, library: library)
        equalizer = EqualizerManager(context: container.mainContext)
        wifi = WiFiTransferController(library: library)
        playback = PlaybackController(library: library)
        playback.setUp()
        recognition = RecognitionController(playback: playback)
        equalizer.onChange = { [weak playback, weak equalizer] in
            guard let playback, let equalizer else { return }
            playback.engine.applyEQ(enabled: equalizer.isEnabled, gains: equalizer.gains, preamp: equalizer.preamp)
        }
        equalizer.onChange?()

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        AppLogger.shared.log("app", "Запуск PlayMyDisk \(version) (сборка \(build))")
    }

    /// Задачи при запуске: сканирование библиотеки и восстановление воспроизведения.
    func runLaunchTasks() async {
        guard !didFinishLaunchTasks else { return }
        await library.rescan()
        if recognition.isPresented {
            // Приложение открыто кнопкой «Распознать» — музыку включим после распознавания
            if playback.restoreOnLaunch(allowAutoplay: false) {
                recognition.resumeWhenClosed()
            }
        } else {
            playback.restoreOnLaunch()
        }
        didFinishLaunchTasks = true
        // Фоновый анализ громкости для выравнивания
        playback.analyzeLibraryLoudness()
    }
}
