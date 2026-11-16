import Foundation
import AVFoundation

/// Глава аудиокниги.
struct ChapterInfo: Identifiable, Sendable, Equatable {
    let id: Int
    let title: String
    /// Начало и конец, секунды.
    let start: Double
    let end: Double
}

/// Чтение глав из файла (.m4b, а также .m4a/.mp3, если AVFoundation их отдаёт).
enum ChapterLoader {
    static func load(url: URL) async -> [ChapterInfo] {
        let asset = AVURLAsset(url: url)
        let languages = Locale.preferredLanguages
        guard let groups = try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: languages),
              !groups.isEmpty else {
            return []
        }
        var result: [ChapterInfo] = []
        for (index, group) in groups.enumerated() {
            let start = CMTimeGetSeconds(group.timeRange.start)
            let length = CMTimeGetSeconds(group.timeRange.duration)
            guard start.isFinite else { continue }
            var title = ""
            let titles = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle)
            if let item = titles.first, let value = try? await item.load(.stringValue) {
                title = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if title.isEmpty {
                title = "Глава \(index + 1)"
            }
            let end = length.isFinite ? start + length : start
            result.append(ChapterInfo(id: index, title: title, start: start, end: end))
        }
        return result
    }
}
