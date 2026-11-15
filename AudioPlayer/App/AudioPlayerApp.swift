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
                    // Первое сканирование библиотеки при запуске
                    await container.library.rescan()
                }
                .onOpenURL { url in
                    // «Поделиться → Открыть в PlayMyDisk»
                    Task {
                        _ = await container.library.importFiles([url])
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Вернулись в приложение — файлы могли добавить через «Файлы»
            if newPhase == .active {
                Task {
                    await container.library.rescan()
                }
            }
        }
    }
}
