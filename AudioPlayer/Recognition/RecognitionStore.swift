import Foundation
import Observation

/// Запись в истории распознаваний.
struct RecognitionEntry: Codable, Identifiable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        /// Фрагмент сохранён и ждёт повторной попытки при хорошей сети.
        case pending
        case found
        /// Попытки исчерпаны — песня не найдена.
        case notFound
    }

    let id: UUID
    let date: Date
    var status: Status
    var song: RecognizedSong?
    /// Имя файла с фрагментом (для ожидающих).
    var signatureFile: String?
    var attempts: Int
}

/// История распознаваний и буфер отложенных фрагментов (JSON + файлы фрагментов).
@MainActor
@Observable
final class RecognitionStore {
    private(set) var entries: [RecognitionEntry] = []

    /// Сколько раз повторять отложенный фрагмент, прежде чем признать «не найдено».
    static let maxAttempts = 3

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let indexURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Recognition", isDirectory: true)
        indexURL = directory.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    var pending: [RecognitionEntry] { entries.filter { $0.status == .pending } }

    func addFound(_ song: RecognizedSong) {
        entries.insert(RecognitionEntry(id: UUID(), date: .now, status: .found, song: song, signatureFile: nil, attempts: 0), at: 0)
        save()
    }

    /// Сохраняет фрагмент в буфер. Возвращает false, если записать не удалось.
    @discardableResult
    func addPending(signature: Data) -> Bool {
        let id = UUID()
        let fileName = "\(id.uuidString).shazamsignature"
        do {
            try signature.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        } catch {
            AppLogger.shared.log("shazam", "Не удалось сохранить фрагмент: \(error.localizedDescription)")
            return false
        }
        entries.insert(RecognitionEntry(id: id, date: .now, status: .pending, song: nil, signatureFile: fileName, attempts: 0), at: 0)
        save()
        return true
    }

    func signatureData(for entry: RecognitionEntry) -> Data? {
        guard let file = entry.signatureFile else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(file))
    }

    func markFound(_ id: UUID, song: RecognizedSong) {
        update(id) { entry in
            entry.status = .found
            entry.song = song
        }
    }

    /// Неудачная попытка; после лимита — «не найдено».
    func markAttemptFailed(_ id: UUID) {
        update(id) { entry in
            entry.attempts += 1
            if entry.attempts >= Self.maxAttempts {
                entry.status = .notFound
            }
        }
    }

    func delete(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        removeSignatureFile(entries[index])
        entries.remove(at: index)
        save()
    }

    func clearFinished() {
        entries.removeAll { $0.status != .pending }
        save()
    }

    // MARK: - Внутреннее

    private func update(_ id: UUID, _ change: (inout RecognitionEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
        if entries[index].status != .pending {
            removeSignatureFile(entries[index])
            entries[index].signatureFile = nil
        }
        save()
    }

    private func removeSignatureFile(_ entry: RecognitionEntry) {
        guard let file = entry.signatureFile else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        do {
            entries = try JSONDecoder().decode([RecognitionEntry].self, from: data)
        } catch {
            AppLogger.shared.log("shazam", "История распознаваний не прочиталась: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            AppLogger.shared.log("shazam", "История распознаваний не сохранилась: \(error.localizedDescription)")
        }
    }
}
