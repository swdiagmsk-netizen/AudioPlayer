import Foundation
import UniformTypeIdentifiers

/// Поддерживаемые форматы файлов.
enum AudioFormats {
    /// Расширения, которые приложение воспроизводит.
    static let playableExtensions: Set<String> = [
        "mp3", "aac", "m4a", "m4b", "m4r", "flac", "wav", "aiff", "aif", "aifc", "caf"
    ]

    /// Защищённые форматы: добавить можно, воспроизвести нельзя.
    /// .m4p — FairPlay (iTunes Store), .aa/.aax — Audible.
    static let protectedExtensions: Set<String> = ["m4p", "aa", "aax"]

    /// Все расширения, которые попадают в библиотеку.
    static let allExtensions: Set<String> = playableExtensions.union(protectedExtensions)

    /// Типы для окна выбора файлов.
    static let importTypes: [UTType] = {
        var types: [UTType] = [.audio]
        for ext in allExtensions.sorted() {
            if let utType = UTType(filenameExtension: ext), !types.contains(utType) {
                types.append(utType)
            }
        }
        return types
    }()

    static func isSupported(_ url: URL) -> Bool {
        allExtensions.contains(url.pathExtension.lowercased())
    }

    /// Формат всегда защищён, независимо от содержимого.
    static func isAlwaysProtected(extension ext: String) -> Bool {
        let e = ext.lowercased()
        return e == "aa" || e == "aax"
    }

    /// Короткое название формата для показа.
    static func displayName(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "MP3"
        case "aac": return "AAC"
        case "m4a": return "M4A"
        case "m4b": return "M4B"
        case "m4r": return "M4R"
        case "m4p": return "M4P"
        case "flac": return "FLAC"
        case "wav": return "WAV"
        case "aiff", "aif": return "AIFF"
        case "aifc": return "AIFC"
        case "caf": return "CAF"
        case "aa": return "AA"
        case "aax": return "AAX"
        default: return ext.uppercased()
        }
    }
}
