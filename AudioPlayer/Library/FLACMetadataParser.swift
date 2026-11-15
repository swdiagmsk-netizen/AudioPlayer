import Foundation

/// Теги FLAC-файла, прочитанные напрямую из блоков метаданных.
struct FLACTags: Sendable {
    /// Поля Vorbis Comment. Ключи приведены к верхнему регистру: TITLE, ARTIST, ALBUM…
    var fields: [String: String] = [:]
    /// Обложка из блока PICTURE (обычно JPEG или PNG).
    var picture: Data?
}

/// Лёгкий разборщик FLAC: блоки VORBIS_COMMENT (тип 4) и PICTURE (тип 6).
/// Нужен как запасной путь: AVFoundation не всегда отдаёт теги FLAC.
enum FLACMetadataParser {
    /// Обложки больше этого размера не читаем, чтобы не забивать память.
    private static let maxPictureBytes = 20_000_000
    private static let maxCommentBytes = 4_000_000

    static func parse(url: URL) -> FLACTags? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            // В начале FLAC может стоять тег ID3v2 — пропускаем его.
            guard var magic = try handle.read(upToCount: 4), magic.count == 4 else { return nil }
            if magic.prefix(3) == Data("ID3".utf8) {
                guard let rest = try handle.read(upToCount: 6), rest.count == 6 else { return nil }
                // Размер ID3 — 4 байта по 7 бит (syncsafe)
                let b = [UInt8](rest.suffix(4))
                let size = (UInt64(b[0] & 0x7F) << 21) | (UInt64(b[1] & 0x7F) << 14)
                    | (UInt64(b[2] & 0x7F) << 7) | UInt64(b[3] & 0x7F)
                try handle.seek(toOffset: 10 + size)
                guard let m = try handle.read(upToCount: 4), m.count == 4 else { return nil }
                magic = m
            }
            guard magic == Data("fLaC".utf8) else { return nil }

            var tags = FLACTags()
            var isLast = false
            var guardCounter = 0
            while !isLast && guardCounter < 256 {
                guardCounter += 1
                guard let header = try handle.read(upToCount: 4), header.count == 4 else { break }
                let h = [UInt8](header)
                isLast = (h[0] & 0x80) != 0
                let blockType = h[0] & 0x7F
                let length = (Int(h[1]) << 16) | (Int(h[2]) << 8) | Int(h[3])
                let bodyStart = try handle.offset()

                if blockType == 4, length <= maxCommentBytes {
                    if let body = try handle.read(upToCount: length), body.count == length {
                        parseVorbisComment([UInt8](body), into: &tags)
                    }
                } else if blockType == 6, tags.picture == nil, length <= maxPictureBytes {
                    if let body = try handle.read(upToCount: length), body.count == length {
                        tags.picture = parsePicture([UInt8](body))
                    }
                }
                // Переходим к следующему блоку независимо от того, читали ли этот
                try handle.seek(toOffset: bodyStart + UInt64(length))
            }
            return tags
        } catch {
            return nil
        }
    }

    // MARK: - Разбор блоков

    /// VORBIS_COMMENT: длины записаны в little-endian.
    private static func parseVorbisComment(_ bytes: [UInt8], into tags: inout FLACTags) {
        var pos = 0
        guard let vendorLength = readLE32(bytes, &pos) else { return }
        pos += vendorLength
        guard pos <= bytes.count, let count = readLE32(bytes, &pos) else { return }
        var index = 0
        while index < count {
            index += 1
            guard let len = readLE32(bytes, &pos), len >= 0, pos + len <= bytes.count else { return }
            let entry = String(decoding: bytes[pos..<(pos + len)], as: UTF8.self)
            pos += len
            guard let eq = entry.firstIndex(of: "=") else { continue }
            let key = entry[entry.startIndex..<eq].uppercased()
            let value = String(entry[entry.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { continue }
            if tags.fields[key] == nil {
                tags.fields[key] = value
            }
        }
    }

    /// PICTURE: длины записаны в big-endian.
    private static func parsePicture(_ bytes: [UInt8]) -> Data? {
        var pos = 0
        guard readBE32(bytes, &pos) != nil else { return nil }            // тип картинки
        guard let mimeLength = readBE32(bytes, &pos) else { return nil }
        pos += mimeLength
        guard pos <= bytes.count, let descLength = readBE32(bytes, &pos) else { return nil }
        pos += descLength
        pos += 16                                                          // ширина, высота, глубина, цвета
        guard pos <= bytes.count, let dataLength = readBE32(bytes, &pos) else { return nil }
        guard dataLength > 0, pos + dataLength <= bytes.count else { return nil }
        return Data(bytes[pos..<(pos + dataLength)])
    }

    private static func readLE32(_ bytes: [UInt8], _ pos: inout Int) -> Int? {
        guard pos >= 0, pos + 4 <= bytes.count else { return nil }
        let value = Int(bytes[pos]) | (Int(bytes[pos + 1]) << 8) | (Int(bytes[pos + 2]) << 16) | (Int(bytes[pos + 3]) << 24)
        pos += 4
        return value
    }

    private static func readBE32(_ bytes: [UInt8], _ pos: inout Int) -> Int? {
        guard pos >= 0, pos + 4 <= bytes.count else { return nil }
        let value = (Int(bytes[pos]) << 24) | (Int(bytes[pos + 1]) << 16) | (Int(bytes[pos + 2]) << 8) | Int(bytes[pos + 3])
        pos += 4
        return value
    }
}
