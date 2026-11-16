import SwiftUI
import UIKit
import Observation

/// Управление Wi-Fi-сервером для интерфейса (главный актор).
@MainActor
@Observable
final class WiFiTransferController {
    private(set) var status = WiFiServerStatus()
    private(set) var address: String?
    /// Принятые за этот сеанс файлы.
    private(set) var received: [String] = []

    @ObservationIgnored private let server = WiFiTransferServer()
    @ObservationIgnored private let library: LibraryAndBookmarkManager
    @ObservationIgnored private var rescanTask: Task<Void, Never>?

    init(library: LibraryAndBookmarkManager) {
        self.library = library
        server.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.status = status
            }
        }
        server.onFileReceived = { [weak self] path in
            Task { @MainActor in
                self?.fileReceived(path)
            }
        }
    }

    var url: String? {
        guard status.isRunning, let address else { return nil }
        return "http://\(address):\(status.port)"
    }

    func start() {
        address = WiFiTransferServer.wifiAddress()
        received = []
        server.start()
        // Экран не гаснет, пока идёт передача: в фоне iOS остановит сервер
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        server.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func fileReceived(_ path: String) {
        received.insert((path as NSString).lastPathComponent, at: 0)
        // Пересканирование — не чаще раза в 2 секунды
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.library.rescan()
        }
    }
}

/// Экран «Wi-Fi-импорт»: адрес для браузера, PIN, принятые файлы.
struct WiFiTransferView: View {
    let controller: WiFiTransferController

    var body: some View {
        List {
            Section {
                if controller.address == nil && !controller.status.isRunning {
                    Label("iPhone не подключён к Wi-Fi. Подключитесь к той же сети, что и компьютер.", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                }
                if let url = controller.url {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Откройте в браузере на компьютере:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(url)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                        Text("PIN: \(controller.status.pin)")
                            .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                            .foregroundStyle(.tint)
                    }
                    .padding(.vertical, 6)
                } else if controller.status.isRunning {
                    Text("Сервер запущен, но адрес в сети Wi-Fi не найден. Проверьте подключение к Wi-Fi.")
                        .foregroundStyle(.secondary)
                }
                if let error = controller.status.error {
                    Text(error).foregroundStyle(.red)
                }
                Button(controller.status.isRunning ? "Остановить" : "Запустить Wi-Fi-импорт") {
                    Haptics.tap()
                    if controller.status.isRunning {
                        controller.stop()
                    } else {
                        controller.start()
                    }
                }
                .fontWeight(.semibold)
            } footer: {
                Text("Не сворачивайте приложение, пока идёт передача: в фоне iOS остановит приём файлов.")
            }

            Section("Как передать музыку") {
                Text("1. Подключите iPhone и компьютер к одной сети Wi-Fi.")
                Text("2. Нажмите «Запустить» и откройте показанный адрес в браузере на компьютере.")
                Text("3. Введите PIN, выберите папку и перетащите файлы в окно браузера.")
            }
            .font(.subheadline)

            if !controller.received.isEmpty {
                Section("Принято (\(controller.received.count))") {
                    ForEach(Array(controller.received.enumerated()), id: \.offset) { _, name in
                        Label(name, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .navigationTitle("Wi-Fi-импорт")
        .onDisappear {
            controller.stop()
        }
    }
}
