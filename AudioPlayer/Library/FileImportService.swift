import Foundation

/// Ошибка импорта с понятным текстом.
struct ImportFailure: Error, Sendable {
    let message: String
}

/// Итог импорта для показа пользователю.
struct ImportReport: Sendable {
    /// Имена добавленных файлов.
    var added: [String] = []
    /// Пропущенные (неподдерживаемый формат).
    var skipped: [String] = []
    /// Ошибки: "имя — причина".
    var failed: [String] = []

    var isEmpty: Bool { added.isEmpty && skipped.isEmpty && failed.isEmpty }
}

/// Копирование выбранных файлов в библиотеку.
enum FileImportService {

    /// Копирует файл в папку библиотеки (относительный путь, "" — корень).
    /// Возвращает имя, под которым файл сохранён.
    /// Файл из «Файлов» или облака доступен только внутри security scope,
    /// а облачный может быть ещё не скачан — поэтому копируем через NSFileCoordinator.
    static func copyIntoLibrary(source: URL, folder: String) -> Result<String, ImportFailure> {
        let fm = FileManager.default
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped { source.stopAccessingSecurityScopedResource() }
        }

        let targetDir = LibraryPaths.url(forRelative: folder)
        do {
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        } catch {
            return .failure(ImportFailure(message: error.localizedDescription))
        }

        let name = LibraryPaths.uniqueName(for: source.lastPathComponent, inFolder: folder)
        let target = targetDir.appendingPathComponent(name)

        var coordinatorError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinatorError) { readableURL in
            do {
                try fm.copyItem(at: readableURL, to: target)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError {
            return .failure(ImportFailure(message: coordinatorError.localizedDescription))
        }
        if let copyError {
            return .failure(ImportFailure(message: copyError.localizedDescription))
        }
        return .success(name)
    }
}
