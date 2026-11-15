import AVFoundation
import Observation

/// Простейший плеер этапа 0: один файл через AVAudioEngine.
/// На следующих этапах его заменит полноценный AudioEngineManager.
@MainActor
@Observable
final class SimplePlayer {
    var title: String = "Файл не выбран"
    var status: String = "Нажми «Выбрать файл»"
    var isPlaying: Bool = false
    var hasFile: Bool = false

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let node = AVAudioPlayerNode()

    init() {
        engine.attach(node)
    }

    /// Копирует выбранный файл в Documents приложения и запускает его.
    func importAndPlay(from pickedURL: URL) {
        // Файл из «Файлов»/облака доступен только внутри security scope
        let scoped = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { pickedURL.stopAccessingSecurityScopedResource() }
        }

        do {
            let fm = FileManager.default
            let documents = try fm.url(for: .documentDirectory,
                                       in: .userDomainMask,
                                       appropriateFor: nil,
                                       create: true)
            let destination = documents.appendingPathComponent(pickedURL.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: pickedURL, to: destination)
            try play(url: destination)
        } catch {
            status = "Ошибка: \(error.localizedDescription)"
            isPlaying = false
        }
    }

    private func play(url: URL) throws {
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

        title = url.lastPathComponent
        status = "Играет"
        isPlaying = true
        hasFile = true
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
            }
        }
    }
}
