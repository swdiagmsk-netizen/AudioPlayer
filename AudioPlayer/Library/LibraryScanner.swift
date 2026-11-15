import Foundation

/// Файл, найденный при обходе Documents.
struct ScannedFile: Sendable {
    let relativePath: String
    let size: Int64
}

/// Обход файловой системы. Функции синхронные и не привязаны к главному потоку —
/// их вызывают из фоновой задачи.
enum LibraryScanner {

    /// Переносит файлы из Documents/Inbox (туда iOS кладёт «Открыть в…») в корень библиотеки.
    static func drainInbox() {
        let fm = FileManager.default
        let inbox = LibraryPaths.inbox
        guard let names = try? fm.contentsOfDirectory(atPath: inbox.path) else { return }
        for name in names {
            let source = inbox.appendingPathComponent(name)
            guard AudioFormats.isSupported(source) else { continue }
            let targetName = LibraryPaths.uniqueName(for: name, inFolder: "")
            let target = LibraryPaths.documents.appendingPathComponent(targetName)
            do {
                try fm.moveItem(at: source, to: target)
            } catch {
                AppLogger.shared.log("scan", "Не удалось перенести из Inbox: \(name) — \(error.localizedDescription)")
            }
        }
    }

    /// Рекурсивно находит все аудиофайлы в Documents.
    static func scanDocuments() -> [ScannedFile] {
        let fm = FileManager.default
        let root = LibraryPaths.documents
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [ScannedFile] = []
        while let item = enumerator.nextObject() as? URL {
            guard AudioFormats.isSupported(item) else { continue }
            let values = try? item.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            guard let relative = LibraryPaths.relativePath(for: item), !relative.isEmpty else { continue }
            // Файлы, оставшиеся в Inbox, в библиотеку не берём
            if relative.hasPrefix("Inbox/") { continue }
            result.append(ScannedFile(relativePath: relative, size: Int64(values?.fileSize ?? 0)))
        }
        return result
    }

    /// Подпапки в заданной папке (относительный путь, "" — корень), по алфавиту.
    static func subfolders(of folder: String) -> [String] {
        let fm = FileManager.default
        let dir = LibraryPaths.url(forRelative: folder)
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        var result: [String] = []
        for name in names {
            if name.hasPrefix(".") { continue }
            if folder.isEmpty && name == "Inbox" { continue }
            var isDir: ObjCBool = false
            let path = dir.appendingPathComponent(name).path
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                result.append(name)
            }
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
