import AVFoundation
import Observation

/// Временный простой плеер: один файл через AVAudioEngine.
/// На этапе 2 его заменит полноценный AudioEngineManager.
@MainActor
@Observable
final class SimplePlayer {
    var title: String = ""
    var status: String = ""
    var isPlaying: Bool = false
    var hasFile: Bool = false

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let node = AVAudioPlayerNode()

    init() {
        engine.attach(node)
    }

    /// Запускает файл из библиотеки.
    func playFile(at url: URL, title: String) {
        do {
            // Категория .playback — звук продолжается при заблокированном экране
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let file = try AVAudioFile(forReading: url)

            node.stop()
            // Подключаем узел с форматом конкретного файла (частота/каналы)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            if !engine.isRunning {
                try engine.start()
            }
            node.scheduleFile(file, at: nil, completionHandler: nil)
            node.play()

            self.title = title
            status = "Играет"
            isPlaying = true
            hasFile = true
        } catch {
            status = "Ошибка: \(error.localizedDescription)"
            isPlaying = false
            AppLogger.shared.log("audio", "Не удалось воспроизвести \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func togglePlayPause() {
        guard hasFile else { return }
        if isPlaying {
            node.pause()
            isPlaying = false
            status = "Пауза"
        } else {
            do {
                if !engine.isRunning {
                    try engine.start()
                }
                node.play()
                isPlaying = true
                status = "Играет"
            } catch {
                status = "Ошибка: \(error.localizedDescription)"
                AppLogger.shared.log("audio", "Не удалось продолжить воспроизведение: \(error.localizedDescription)")
            }
        }
    }
}
