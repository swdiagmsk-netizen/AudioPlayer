import Foundation

/// Пути библиотеки. Вся музыка лежит в Documents (видна в приложении «Файлы»).
enum LibraryPaths {
    /// Папка Documents приложения. Симлинки раскрыты, чтобы пути
    /// совпадали с теми, что возвращает обход файловой системы.
    static let documents: URL = {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return url.resolvingSymlinksInPath()
    }()

    /// Папка, куда iOS кладёт файлы из «Открыть в…».
    static var inbox: URL {
        documents.appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Полный путь по относительному ("" — сама папка Documents).
    static func url(forRelative relative: String) -> URL {
        if relative.isEmpty { return documents }
        return documents.appendingPathComponent(relative)
    }

    /// Относительный путь для файла внутри Documents; nil — если файл снаружи.
    static func relativePath(for url: URL) -> String? {
        let root = documents.path
        let full = url.resolvingSymlinksInPath().path
        guard full.hasPrefix(root) else { return nil }
        var rel = String(full.dropFirst(root.count))
        while rel.hasPrefix("/") { rel.removeFirst() }
        return rel
    }

    /// Папка, в которой лежит элемент ("" — корень).
    static func parentFolder(ofRelative relative: String) -> String {
        let ns = relative as NSString
        let parent = ns.deletingLastPathComponent
        return parent == "/" ? "" : parent
    }

    /// Склеивает папку и имя в относительный путь.
    static func join(_ folder: String, _ name: String) -> String {
        folder.isEmpty ? name : folder + "/" + name
    }

    /// Свободное имя в папке: если "song.mp3" занято, вернёт "song (2).mp3" и т.д.
    static func uniqueName(for name: String, inFolder folder: String) -> String {
        let fm = FileManager.default
        let dir = url(forRelative: folder)
        if !fm.fileExists(atPath: dir.appendingPathComponent(name).path) { return name }
        let ns = name as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            if !fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) { return candidate }
            index += 1
        }
    }
}
