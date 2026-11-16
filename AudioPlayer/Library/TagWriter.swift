import Foundation
import AVFoundation

/// Теги для записи.
struct TagValues: Sendable, Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var albumArtist = ""
    var genre = ""
    var year = ""
    var trackNumber = ""
    var composer = ""
    var comment = ""
}

/// Что делать с обложкой при записи.
enum ArtworkChange: Sendable {
    /// Оставить как есть.
    case keep
    /// Заменить (JPEG).
    case replace(Data)
    /// Удалить.
    case remove
}

/// Результат записи тегов.
enum TagWriteResult: Sendable {
    /// Записано в файл.
    case writtenToFile
    /// Формат не поддерживает запись — сохранено только в приложении.
    case appOnly
    /// Ошибка записи в файл (сохранено в приложении).
    case failed(String)
}

/// Запись тегов в файл:
/// MP3 — свой писатель ID3v2.4; M4A/M4B/M4R — экспорт AVFoundation без перекодирования;
/// FLAC — перезапись блоков VORBIS_COMMENT и PICTURE. WAV/AIFF/CAF/AAC — только в приложении.
/// Файл всегда пишется во временный рядом и атомарно заменяет оригинал.
enum TagWriter {

    /// Поддерживает ли формат запись в файл.
    static func canWrite(extension ext: String) -> Bool {
        ["mp3", "m4a", "m4b", "m4r", "flac"].contains(ext.lowercased())
    }

    static func write(_ tags: TagValues, artwork: ArtworkChange, to url: URL) async -> TagWriteResult {
        let ext = url.pathExtension.lowercased()
        do {
            switch ext {
            case "mp3":
                try ID3Writer.write(tags, artwork: artwork, to: url)
            case "m4a", "m4b", "m4r":
                try await MP4TagWriter.write(tags, artwork: artwork, to: url)
            case "flac":
                try FLACWriter.write(tags, artwork: artwork, to: url)
            default:
                return .appOnly
            }
            return .writtenToFile
        } catch {
            AppLogger.shared.log("tags", "Не удалось записать теги в \(url.lastPathComponent): \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }
}

/// Ошибка записи тегов.
struct TagWriteError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Общие помощники

enum FileRewrite {
    /// Пишет `header`, затем копирует исходный файл начиная с `offset`, во временный файл,
    /// и атомарно заменяет им оригинал. Большие файлы копируются кусками.
    static func replace(_ url: URL, header: Data, copyFrom offset: UInt64) throws {
        let fm = FileManager.default
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        fm.createFile(atPath: temp.path, contents: nil)
        do {
            let output = try FileHandle(forWritingTo: temp)
            let input = try FileHandle(forReadingFrom: url)
            defer {
                try? output.close()
                try? input.close()
            }
            try output.write(contentsOf: header)
            try input.seek(toOffset: offset)
            while true {
                guard let chunk = try input.read(upToCount: 4 * 1_048_576), !chunk.isEmpty else { break }
                try output.write(contentsOf: chunk)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        _ = try fm.replaceItemAt(url, withItemAt: temp)
    }

    static func syncsafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }

    static func readSyncsafe(_ b: [UInt8]) -> Int {
        (Int(b[0] & 0x7F) << 21) | (Int(b[1] & 0x7F) << 14) | (Int(b[2] & 0x7F) << 7) | Int(b[3] & 0x7F)
    }

    static func bigEndian32(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    static func littleEndian32(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }
}

// MARK: - MP3: ID3v2.4

private enum ID3Writer {
    /// Фреймы, которыми управляет редактор (остальные из старого тега сохраняются).
    private static let managed: Set<String> = [
        "TIT2", "TPE1", "TALB", "TPE2", "TCON", "TDRC", "TYER", "TDAT", "TRCK", "TCOM", "COMM"
    ]

    static func write(_ tags: TagValues, artwork: ArtworkChange, to url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        let head = try handle.read(upToCount: 10) ?? Data()
        var audioOffset: UInt64 = 0
        var keptFrames: [(id: String, body: Data)] = []

        if head.count == 10, head.prefix(3) == Data("ID3".utf8) {
            let h = [UInt8](head)
            let version = h[3]
            let flags = h[5]
            let size = FileRewrite.readSyncsafe(Array(h[6...9]))
            let hasFooter = version == 4 && (flags & 0x10) != 0
            audioOffset = UInt64(10 + size + (hasFooter ? 10 : 0))
            let body = try handle.read(upToCount: size) ?? Data()
            // Сохраняем «чужие» фреймы, если тег без unsynchronisation и версия 2.3/2.4
            if (version == 3 || version == 4) && (flags & 0x80) == 0 {
                keptFrames = parseFrames([UInt8](body), version: version, skipExtended: (flags & 0x40) != 0)
            }
        }
        try handle.close()

        var frames: [(String, Data)] = []
        func text(_ id: String, _ value: String) {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            frames.append((id, Data([0x03]) + Data(clean.utf8)))
        }
        text("TIT2", tags.title)
        text("TPE1", tags.artist)
        text("TALB", tags.album)
        text("TPE2", tags.albumArtist)
        text("TCON", tags.genre)
        text("TDRC", tags.year)
        text("TRCK", tags.trackNumber)
        text("TCOM", tags.composer)
        let comment = tags.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !comment.isEmpty {
            frames.append(("COMM", Data([0x03]) + Data("eng".utf8) + Data([0x00]) + Data(comment.utf8)))
        }

        for frame in keptFrames {
            if managed.contains(frame.id) { continue }
            if frame.id == "APIC" {
                if case .keep = artwork { frames.append((frame.id, frame.body)) }
                continue
            }
            frames.append((frame.id, frame.body))
        }
        if case .replace(let jpeg) = artwork {
            var body = Data([0x00])
            body += Data("image/jpeg".utf8) + Data([0x00])
            body += Data([0x03, 0x00])
            body += jpeg
            frames.append(("APIC", body))
        }

        var tagBody = Data()
        for (id, body) in frames {
            tagBody += Data(id.utf8)
            tagBody += Data(FileRewrite.syncsafe(body.count))
            tagBody += Data([0x00, 0x00])
            tagBody += body
        }
        tagBody += Data(count: 1024)

        var header = Data("ID3".utf8)
        header += Data([0x04, 0x00, 0x00])
        header += Data(FileRewrite.syncsafe(tagBody.count))
        header += tagBody

        try FileRewrite.replace(url, header: header, copyFrom: audioOffset)
    }

    private static func parseFrames(_ b: [UInt8], version: UInt8, skipExtended: Bool) -> [(id: String, body: Data)] {
        var pos = 0
        if skipExtended, b.count >= 4 {
            let extSize = version == 4 ? FileRewrite.readSyncsafe(Array(b[0...3])) : (Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])) + 4
            pos = extSize
        }
        var result: [(String, Data)] = []
        while pos + 10 <= b.count {
            let idBytes = b[pos..<(pos + 4)]
            if idBytes.contains(0) { break }
            guard let id = String(bytes: idBytes, encoding: .ascii),
                  id.allSatisfy({ $0.isUppercase || $0.isNumber }) else { break }
            let sizeBytes = Array(b[(pos + 4)...(pos + 7)])
            let size = version == 4
                ? FileRewrite.readSyncsafe(sizeBytes)
                : (Int(sizeBytes[0]) << 24 | Int(sizeBytes[1]) << 16 | Int(sizeBytes[2]) << 8 | Int(sizeBytes[3]))
            let flags2 = b[pos + 9]
            pos += 10
            guard size >= 0, pos + size <= b.count else { break }
            // Сжатые/зашифрованные фреймы не переносим
            let special = version == 4 ? (flags2 & 0x0F) != 0 : (flags2 & 0xE0) != 0
            if !special {
                result.append((id, Data(b[pos..<(pos + size)])))
            }
            pos += size
        }
        return result
    }
}

// MARK: - MP4 (M4A/M4B/M4R)

private enum MP4TagWriter {
    static func write(_ tags: TagValues, artwork: ArtworkChange, to url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let existing = (try? await asset.load(.metadata)) ?? []

        let replaced: Set<AVMetadataIdentifier> = [
            .iTunesMetadataSongName, .iTunesMetadataArtist, .iTunesMetadataAlbum, .iTunesMetadataAlbumArtist,
            .iTunesMetadataUserGenre, .iTunesMetadataReleaseDate, .iTunesMetadataTrackNumber,
            .iTunesMetadataComposer, .iTunesMetadataUserComment,
            .commonIdentifierTitle, .commonIdentifierArtist, .commonIdentifierAlbumName
        ]
        var items: [AVMetadataItem] = []
        for item in existing {
            guard let identifier = item.identifier else { continue }
            if replaced.contains(identifier) { continue }
            if identifier == .iTunesMetadataCoverArt || identifier == .commonIdentifierArtwork {
                if case .keep = artwork { items.append(item) }
                continue
            }
            items.append(item)
        }

        func add(_ identifier: AVMetadataIdentifier, _ value: String) {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = clean as NSString
            item.extendedLanguageTag = "und"
            items.append(item)
        }
        add(.iTunesMetadataSongName, tags.title)
        add(.iTunesMetadataArtist, tags.artist)
        add(.iTunesMetadataAlbum, tags.album)
        add(.iTunesMetadataAlbumArtist, tags.albumArtist)
        add(.iTunesMetadataUserGenre, tags.genre)
        add(.iTunesMetadataReleaseDate, tags.year)
        add(.iTunesMetadataComposer, tags.composer)
        add(.iTunesMetadataUserComment, tags.comment)
        if let number = Int(tags.trackNumber.trimmingCharacters(in: .whitespaces)), number > 0, number < 65_536 {
            // Номер трека в iTunes: 8 байт, номер в байтах 2–3
            let item = AVMutableMetadataItem()
            item.identifier = .iTunesMetadataTrackNumber
            item.value = Data([0, 0, UInt8(number >> 8), UInt8(number & 0xFF), 0, 0, 0, 0]) as NSData
            item.dataType = kCMMetadataBaseDataType_RawData as String
            items.append(item)
        }
        if case .replace(let jpeg) = artwork {
            let item = AVMutableMetadataItem()
            item.identifier = .iTunesMetadataCoverArt
            item.value = jpeg as NSData
            item.dataType = kCMMetadataBaseDataType_JPEG as String
            items.append(item)
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw TagWriteError(message: "Экспорт недоступен")
        }
        session.metadata = items
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(url.pathExtension)")
        // VERIFY: асинхронный экспорт (iOS 18+)
        try await session.export(to: temp, as: .m4a)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}

// MARK: - FLAC

private enum FLACWriter {
    static func write(_ tags: TagValues, artwork: ArtworkChange, to url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var offset: UInt64 = 0
        guard var magic = try handle.read(upToCount: 4), magic.count == 4 else {
            throw TagWriteError(message: "Файл повреждён")
        }
        if magic.prefix(3) == Data("ID3".utf8) {
            guard let rest = try handle.read(upToCount: 6), rest.count == 6 else { throw TagWriteError(message: "Файл повреждён") }
            let size = FileRewrite.readSyncsafe(Array([UInt8](rest).suffix(4)))
            offset = UInt64(10 + size)
            try handle.seek(toOffset: offset)
            guard let m = try handle.read(upToCount: 4), m.count == 4 else { throw TagWriteError(message: "Файл повреждён") }
            magic = m
        }
        guard magic == Data("fLaC".utf8) else { throw TagWriteError(message: "Это не FLAC-файл") }

        // Читаем все блоки метаданных
        var blocks: [(type: UInt8, body: Data)] = []
        var isLast = false
        while !isLast {
            guard let header = try handle.read(upToCount: 4), header.count == 4 else {
                throw TagWriteError(message: "Файл повреждён")
            }
            let h = [UInt8](header)
            isLast = (h[0] & 0x80) != 0
            let type = h[0] & 0x7F
            let length = (Int(h[1]) << 16) | (Int(h[2]) << 8) | Int(h[3])
            guard let body = try handle.read(upToCount: length), body.count == length else {
                throw TagWriteError(message: "Файл повреждён")
            }
            blocks.append((type, body))
        }
        let audioOffset = try handle.offset()

        // Оставляем всё, кроме комментариев, отступов и (если меняется) картинок
        var kept = blocks.filter { block in
            if block.type == 4 || block.type == 1 { return false }
            if block.type == 6, case .keep = artwork { return true }
            if block.type == 6 { return false }
            return true
        }
        // STREAMINFO должен быть первым
        if let streamIndex = kept.firstIndex(where: { $0.type == 0 }), streamIndex != 0 {
            let stream = kept.remove(at: streamIndex)
            kept.insert(stream, at: 0)
        }

        kept.append((4, vorbisComment(tags)))
        if case .replace(let jpeg) = artwork {
            kept.append((6, picture(jpeg)))
        }
        kept.append((1, Data(count: 1024)))

        var header = Data("fLaC".utf8)
        for (index, block) in kept.enumerated() {
            let last = index == kept.count - 1
            guard block.body.count < (1 << 24) else { throw TagWriteError(message: "Слишком большая обложка") }
            header += Data([(last ? 0x80 : 0x00) | block.type])
            header += Data(FileRewrite.bigEndian32(block.body.count).suffix(3))
            header += block.body
        }
        try handle.close()
        try FileRewrite.replace(url, header: header, copyFrom: audioOffset)
    }

    private static func vorbisComment(_ tags: TagValues) -> Data {
        var fields: [String] = []
        func add(_ key: String, _ value: String) {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { fields.append("\(key)=\(clean)") }
        }
        add("TITLE", tags.title)
        add("ARTIST", tags.artist)
        add("ALBUM", tags.album)
        add("ALBUMARTIST", tags.albumArtist)
        add("GENRE", tags.genre)
        add("DATE", tags.year)
        add("TRACKNUMBER", tags.trackNumber)
        add("COMPOSER", tags.composer)
        add("COMMENT", tags.comment)

        let vendor = Data("PlayMyDisk".utf8)
        var data = Data(FileRewrite.littleEndian32(vendor.count)) + vendor
        data += Data(FileRewrite.littleEndian32(fields.count))
        for field in fields {
            let bytes = Data(field.utf8)
            data += Data(FileRewrite.littleEndian32(bytes.count)) + bytes
        }
        return data
    }

    private static func picture(_ jpeg: Data) -> Data {
        let mime = Data("image/jpeg".utf8)
        var data = Data(FileRewrite.bigEndian32(3))
        data += Data(FileRewrite.bigEndian32(mime.count)) + mime
        data += Data(FileRewrite.bigEndian32(0))
        data += Data(FileRewrite.bigEndian32(0)) + Data(FileRewrite.bigEndian32(0))
        data += Data(FileRewrite.bigEndian32(0)) + Data(FileRewrite.bigEndian32(0))
        data += Data(FileRewrite.bigEndian32(jpeg.count)) + jpeg
        return data
    }
}
