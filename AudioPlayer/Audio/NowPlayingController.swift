import Foundation
import MediaPlayer
import UIKit

/// Слабая ссылка на получателя команд, которую можно безопасно
/// передать в обработчики MPRemoteCommandCenter (их вызывает система).
final class RemoteTargetBox: @unchecked Sendable {
    weak var target: PlaybackController?

    init(_ target: PlaybackController) {
        self.target = target
    }
}

/// Экран блокировки и Пункт управления: «Сейчас играет» и кнопки.
@MainActor
final class NowPlayingController {
    private var box: RemoteTargetBox?
    private var cachedArtworkUID: UUID?
    private var cachedArtwork: MPMediaItemArtwork?

    /// Регистрирует обработчики кнопок. Вызывать один раз.
    func installCommands(target: PlaybackController) {
        guard box == nil else { return }
        let newBox = RemoteTargetBox(target)
        box = newBox
        Self.registerHandlers(on: MPRemoteCommandCenter.shared(), box: newBox)
        applyButtonMode()
    }

    /// Обработчики создаются в неизолированной функции: система может вызвать их
    /// не с главного потока, поэтому они сами переходят в главный актор через Task.
    private nonisolated static func registerHandlers(on center: MPRemoteCommandCenter, box: RemoteTargetBox) {
        _ = center.playCommand.addTarget { _ in
            Task { @MainActor in box.target?.play() }
            return .success
        }
        _ = center.pauseCommand.addTarget { _ in
            Task { @MainActor in box.target?.pause() }
            return .success
        }
        _ = center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in box.target?.togglePlayPause() }
            return .success
        }
        _ = center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in box.target?.next() }
            return .success
        }
        _ = center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in box.target?.previous() }
            return .success
        }
        _ = center.skipForwardCommand.addTarget { _ in
            Task { @MainActor in box.target?.skipForward() }
            return .success
        }
        _ = center.skipBackwardCommand.addTarget { _ in
            Task { @MainActor in box.target?.skipBackward() }
            return .success
        }
        _ = center.changePlaybackPositionCommand.addTarget { event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = positionEvent.positionTime
            Task { @MainActor in box.target?.seek(to: position) }
            return .success
        }
        _ = center.changePlaybackRateCommand.addTarget { event in
            guard let rateEvent = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let newRate = rateEvent.playbackRate
            Task { @MainActor in box.target?.setRate(newRate) }
            return .success
        }
    }

    /// Какие кнопки показывать по бокам от Паузы: перемотку ±N или переход между треками.
    /// iOS показывает только три кнопки, поэтому одновременно что-то одно.
    func applyButtonMode() {
        let center = MPRemoteCommandCenter.shared()
        let useSkip = AppSettings.lockScreenUsesSkip
        let interval = NSNumber(value: AppSettings.skipInterval)
        center.skipForwardCommand.preferredIntervals = [interval]
        center.skipBackwardCommand.preferredIntervals = [interval]
        center.skipForwardCommand.isEnabled = useSkip
        center.skipBackwardCommand.isEnabled = useSkip
        center.nextTrackCommand.isEnabled = !useSkip
        center.previousTrackCommand.isEnabled = !useSkip
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackRateCommand.isEnabled = true
        center.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3, 4]
    }

    /// Полное обновление при смене трека.
    func update(track: TrackRecord, duration: Double, elapsed: Double, rate: Float, isPlaying: Bool) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = track.displayTitle
        if !track.artist.isEmpty { info[MPMediaItemPropertyArtist] = track.artist }
        if !track.album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = track.album }
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        if let artwork = artwork(for: track) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Обновление только позиции и скорости (пауза, перемотка, смена скорости).
    func updatePlayback(elapsed: Double, rate: Float, isPlaying: Bool) {
        let center = MPNowPlayingInfoCenter.default()
        guard var info = center.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0
        center.nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Обложка

    private func artwork(for track: TrackRecord) -> MPMediaItemArtwork? {
        if cachedArtworkUID == track.uid { return cachedArtwork }
        cachedArtworkUID = track.uid
        cachedArtwork = nil
        guard track.hasArtwork else { return nil }
        let path = ArtworkCache.url(for: track.uid, thumbnail: false).path
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        cachedArtwork = Self.makeArtwork(image)
        return cachedArtwork
    }

    /// Замыкание обложки система вызывает с фонового потока,
    /// поэтому оно создаётся вне главного актора.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
