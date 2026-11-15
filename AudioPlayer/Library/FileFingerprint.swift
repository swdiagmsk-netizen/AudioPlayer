import Foundation
import CryptoKit

/// Отпечаток файла: размер + SHA-256 первого мегабайта.
/// По нему приложение узнаёт файл после переименования или перемещения
/// и находит дубликаты по содержимому.
enum FileFingerprint {
    private static let sampleSize = 1_048_576

    /// Возвращает строку вида "<размер>-<hex SHA-256>" или nil, если файл не читается.
    static func compute(url: URL) -> String? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let sizeNumber = attrs[.size] as? NSNumber else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head: Data
        do {
            head = try handle.read(upToCount: sampleSize) ?? Data()
        } catch {
            return nil
        }
        let digest = SHA256.hash(data: head)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(sizeNumber.int64Value)-\(hex)"
    }
}
