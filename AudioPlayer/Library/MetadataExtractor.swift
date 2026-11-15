import Foundation
import AVFoundation

/// Всё, что удалось узнать о файле. Простая структура, чтобы безопасно
/// передавать её между потоками.
struct ExtractedMetadata: Sendable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var albumArtist: String = ""
    var genre: String = ""
    var year: String = ""
    var trackNumber: String = ""
    var composer: String = ""
    var comment: String = ""
    var artworkData: Data?
    var duration: Double = 0
    var bitrateKbps: Int = 0
    var sampleRate: Double = 0
    var isProtected: Bool = false
    var isPlayable: Bool = true
}

/// Читает теги и технические сведения из аудиофайла.
enum MetadataExtractor {

    static func extract(url: URL) async -> ExtractedMetadata {
        var result = ExtractedMetadata()
        let ext = url.pathExtension.lowercased()

        // Audible: AVFoundation такие файлы не открывает вовсе
        if AudioFormats.isAlwaysProtected(extension: ext) {
            result.isProtected = true
            result.isPlayable = false
            return result
        }

        let asset = AVURLAsset(url: url)

        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 { result.duration = seconds }
        }
        if let protected = try? await asset.load(.hasProtectedContent) {
            result.isProtected = protected
        }
        if ext == "m4p" { result.isProtected = true }
        if let playable = try? await asset.load(.isPlayable) {
            result.isPlayable = playable && !result.isProtected
        } else {
            result.isPlayable = !result.isProtected
        }

        // Технические параметры первой аудиодорожки
        if let tracks = try? await asset.loadTracks(withMediaType: .audio), let track = tracks.first {
            if let rate = try? await track.load(.estimatedDataRate), rate > 0 {
                result.bitrateKbps = Int((rate / 1000).rounded())
            }
            if let descriptions = try? await track.load(.formatDescriptions), let first = descriptions.first {
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(first) {
                    result.sampleRate = asbd.pointee.mSampleRate
                }
            }
        }

        // Теги: сначала «общие», затем форматные (ID3, iTunes)
        let common = (try? await asset.load(.commonMetadata)) ?? []
        let all = (try? await asset.load(.metadata)) ?? []

        result.title = await string(common, [.commonIdentifierTitle]) ?? ""
        result.artist = await string(common, [.commonIdentifierArtist]) ?? ""
        result.album = await string(common, [.commonIdentifierAlbumName]) ?? ""
        result.albumArtist = await string(all, [.id3MetadataBand, .iTunesMetadataAlbumArtist]) ?? ""
        var genre = await string(all, [.id3MetadataContentType, .iTunesMetadataUserGenre])
        if genre == nil {
            genre = await string(common, [.commonIdentifierType])
        }
        result.genre = genre ?? ""

        var rawYear = await string(all, [.id3MetadataRecordingTime, .id3MetadataYear, .iTunesMetadataReleaseDate])
        if rawYear == nil {
            rawYear = await string(common, [.commonIdentifierCreationDate])
        }
        result.year = yearOnly(rawYear ?? "")
        result.trackNumber = await trackNumber(all)
        result.composer = await string(all, [.id3MetadataComposer, .iTunesMetadataComposer]) ?? ""
        result.comment = await string(all, [.id3MetadataComments, .iTunesMetadataUserComment]) ?? ""
        result.artworkData = await data(common, [.commonIdentifierArtwork])

        // FLAC: если AVFoundation не отдал теги — читаем блоки сами
        if ext == "flac", let flac = FLACMetadataParser.parse(url: url) {
            mergeFLAC(flac, into: &result)
        }
        return result
    }

    // MARK: - Помощники

    /// Первое непустое строковое значение по списку идентификаторов.
    private static func string(_ items: [AVMetadataItem], _ identifiers: [AVMetadataIdentifier]) async -> String? {
        for identifier in identifiers {
            let matches = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier)
            for item in matches {
                if let value = try? await item.load(.stringValue) {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return nil
    }

    /// Первое непустое бинарное значение (обложка).
    private static func data(_ items: [AVMetadataItem], _ identifiers: [AVMetadataIdentifier]) async -> Data? {
        for identifier in identifiers {
            let matches = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier)
            for item in matches {
                if let value = try? await item.load(.dataValue), !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    /// Номер трека: в ID3 это строка "3/12", в iTunes — 8 байт (номер в байтах 2–3).
    private static func trackNumber(_ items: [AVMetadataItem]) async -> String {
        if let text = await string(items, [.id3MetadataTrackNumber]) {
            let first = text.split(separator: "/").first.map(String.init) ?? text
            return first.trimmingCharacters(in: .whitespaces)
        }
        let matches = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataTrackNumber)
        for item in matches {
            if let value = try? await item.load(.dataValue), value.count >= 4 {
                let bytes = [UInt8](value)
                let number = (Int(bytes[2]) << 8) | Int(bytes[3])
                if number > 0 { return String(number) }
            }
            if let text = try? await item.load(.stringValue), !text.isEmpty {
                return text
            }
        }
        return ""
    }

    /// Из "2019-05-01T00:00:00Z" оставляет "2019".
    private static func yearOnly(_ raw: String) -> String {
        let digits = raw.prefix(4)
        if digits.count == 4, digits.allSatisfy({ $0.isNumber }) { return String(digits) }
        return raw
    }

    /// Дополняет пустые поля значениями из FLAC-блоков.
    private static func mergeFLAC(_ flac: FLACTags, into result: inout ExtractedMetadata) {
        func pick(_ current: String, _ keys: [String]) -> String {
            if !current.isEmpty { return current }
            for key in keys {
                if let value = flac.fields[key], !value.isEmpty { return value }
            }
            return current
        }
        result.title = pick(result.title, ["TITLE"])
        result.artist = pick(result.artist, ["ARTIST"])
        result.album = pick(result.album, ["ALBUM"])
        result.albumArtist = pick(result.albumArtist, ["ALBUMARTIST", "ALBUM ARTIST"])
        result.genre = pick(result.genre, ["GENRE"])
        result.year = yearOnly(pick(result.year, ["DATE", "YEAR"]))
        result.trackNumber = pick(result.trackNumber, ["TRACKNUMBER"])
        result.composer = pick(result.composer, ["COMPOSER"])
        result.comment = pick(result.comment, ["COMMENT", "DESCRIPTION"])
        if result.artworkData == nil, let picture = flac.picture {
            result.artworkData = picture
        }
    }
}
