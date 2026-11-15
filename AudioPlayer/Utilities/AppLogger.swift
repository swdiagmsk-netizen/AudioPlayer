import Foundation

/// Журнал отладки в файле. Без Xcode это единственный способ понять,
/// что пошло не так на телефоне. Потокобезопасен: вся работа с файлом
/// идёт на одной последовательной очереди.
final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    /// Файл журнала (его можно отправить через «Поделиться»).
    let fileURL: URL

    private let queue = DispatchQueue(label: "playmydisk.logger")
    private let maxBytes: Int = 2_000_000
    private let formatter: DateFormatter

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Logs", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("debug.log")

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter = f
    }

    /// Добавляет строку в журнал. `category` — короткая метка модуля: "audio", "import" и т.п.
    func log(_ category: String, _ message: String) {
        let now = Date()
        queue.async { [self] in
            let line = "\(formatter.string(from: now)) [\(category)] \(message)\n"
            append(line)
        }
    }

    /// Весь текст журнала.
    func readAll() -> String {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
    }

    /// Очищает журнал.
    func clear() {
        queue.sync {
            _ = try? Data().write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Внутреннее (вызывается только на очереди)

    private func append(_ line: String) {
        let fm = FileManager.default
        let data = Data(line.utf8)
        if !fm.fileExists(atPath: fileURL.path) {
            try? data.write(to: fileURL, options: .atomic)
            return
        }
        rotateIfNeeded()
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Журнал не должен ронять приложение
        }
    }

    /// Если файл вырос больше лимита — оставляем только вторую половину.
    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > maxBytes,
              let data = try? Data(contentsOf: fileURL) else { return }
        let keep = data.suffix(maxBytes / 2)
        try? Data(keep).write(to: fileURL, options: .atomic)
    }
}
