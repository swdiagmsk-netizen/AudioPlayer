import SwiftUI

/// Точка входа PlayMyDisk.
@main
struct AudioPlayerApp: App {
    @State private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.themeMode) private var themeMode = "auto"

    var body: some Scene {
        WindowGroup {
            ContentView(container: container)
                .preferredColorScheme(themeMode == "light" ? .light : (themeMode == "dark" ? .dark : nil))
                .task {
                    // Сканирование библиотеки и продолжение с места остановки
                    await container.runLaunchTasks()
                }
                .onOpenURL { url in
                    // «Поделиться → Открыть в PlayMyDisk»
                    Task {
                        _ = await container.library.importFiles([url])
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                container.playback.setVisualizerActive(true)
                container.recognition.processPendingIfOnline()
                if RecognitionRequest.consume() {
                    container.recognition.start()
                }
                // Вернулись в приложение — файлы могли добавить через «Файлы»
                if container.didFinishLaunchTasks {
                    Task {
                        await container.library.rescan()
                    }
                }
            case .background, .inactive:
                // Сохраняем позицию, чтобы продолжить с того же места после закрытия
                container.playback.saveAll()
                if newPhase == .background {
                    container.playback.setVisualizerActive(false)
                }
            @unknown default:
                break
            }
        }
    }
}
