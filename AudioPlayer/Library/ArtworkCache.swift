import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Кэш обложек на диске: Library/Caches/Artwork/<uid>.jpg и <uid>_thumb.jpg.
/// Кэш можно очистить — обложки извлекутся из файлов заново при пересканировании.
enum ArtworkCache {
    private static let fullSize = 600
    private static let thumbSize = 160

    static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Artwork", isDirectory: true)
    }

    /// Путь к обложке трека. `thumbnail` — маленькая версия для списка.
    static func url(for uid: UUID, thumbnail: Bool) -> URL {
        let name = thumbnail ? "\(uid.uuidString)_thumb.jpg" : "\(uid.uuidString).jpg"
        return directory.appendingPathComponent(name)
    }

    /// Уменьшает картинку и сохраняет обе версии. Возвращает true при успехе.
    @discardableResult
    static func store(imageData: Data, for uid: UUID) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let full = downscaledJPEG(from: imageData, maxPixel: fullSize),
              let thumb = downscaledJPEG(from: imageData, maxPixel: thumbSize) else { return false }
        do {
            try full.write(to: url(for: uid, thumbnail: false), options: .atomic)
            try thumb.write(to: url(for: uid, thumbnail: true), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func exists(for uid: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: uid, thumbnail: false).path)
    }

    static func remove(for uid: UUID) {
        let fm = FileManager.default
        try? fm.removeItem(at: url(for: uid, thumbnail: false))
        try? fm.removeItem(at: url(for: uid, thumbnail: true))
    }

    /// Размер кэша в байтах.
    static func totalSize() -> Int64 {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var total: Int64 = 0
        for name in names {
            let path = directory.appendingPathComponent(name).path
            if let attrs = try? fm.attributesOfItem(atPath: path), let size = attrs[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    /// Удаляет все обложки из кэша.
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// JPEG не больше `maxPixel` по длинной стороне (для записи обложки в файл).
    static func jpegData(from data: Data, maxPixel: Int) -> Data? {
        downscaledJPEG(from: data, maxPixel: maxPixel)
    }

    // MARK: - Уменьшение картинки (ImageIO, можно вызывать с любого потока)

    private static func downscaledJPEG(from data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
