import SwiftUI

/// Точка входа PlayMyDisk.
@main
struct AudioPlayerApp: App {
    @State private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(container: container)
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
                // Вернулись в приложение — файлы могли добавить через «Файлы»
                if container.didFinishLaunchTasks {
                    Task {
                        await container.library.rescan()
                    }
                }
            case .background, .inactive:
                // Сохраняем позицию, чтобы продолжить с того же места после закрытия
                container.playback.saveState()
            @unknown default:
                break
            }
        }
    }
}
