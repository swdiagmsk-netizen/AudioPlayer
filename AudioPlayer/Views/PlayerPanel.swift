import SwiftUI
import UIKit

/// Верхняя панель плеера: ЖК-дисплей, перемотка, кнопки управления.
struct PlayerPanel: View {
    let playback: PlaybackController
    /// Номер строки играющего трека в открытом списке (nil — трек не из этого списка).
    let currentRowNumber: Int?
    let onImport: () -> Void
    let onSettings: () -> Void
    let onBookmark: () -> Void
    let onBookmarksList: () -> Void
    let onEqualizer: () -> Void
    let onSleepTimer: () -> Void
    let onChapters: () -> Void
    let onRecognize: () -> Void

    @Environment(\.palette) private var palette
    @AppStorage(SettingsKeys.skipInterval) private var skipInterval: Int = 15
    @AppStorage(SettingsKeys.skin) private var skin = "classic"
    @AppStorage(SettingsKeys.retroStyle) private var retroStyle = "cassette"
    @AppStorage(SettingsKeys.visualizer) private var visualizer = VisualizerKind.bars.rawValue
    @AppStorage(SettingsKeys.lineColorHex) private var lineColorHex = "#6CFF7E"

    /// Car Mode: крупные кнопки.
    private var big: CGFloat { skin == "car" ? 1.3 : 1 }

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    private var engine: AudioEngineManager { playback.engine }
    private var hasTrack: Bool { playback.currentTrack != nil }

    var body: some View {
        VStack(spacing: 12) {
            display
            progress
            mainControls
            secondaryControls
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(palette.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.line).frame(height: 1)
        }
    }

    // MARK: - Дисплей по скину

    private var visualizerKind: VisualizerKind {
        VisualizerKind(rawValue: visualizer) ?? .bars
    }

    @ViewBuilder
    private var display: some View {
        let time = isDragging ? dragValue : engine.currentTime
        switch skin {
        case "modern":
            ModernDisplay(playback: playback, time: time)
        case "retro":
            RetroDisplay(playback: playback, time: time, vinyl: retroStyle == "vinyl")
        case "car":
            CarDisplay(playback: playback, rowNumber: currentRowNumber, time: time)
        default:
            LCDDisplay(
                track: playback.currentTrack,
                rowNumber: currentRowNumber,
                time: time,
                isPlaying: engine.isPlaying,
                chapterTitle: playback.currentChapter?.title,
                spectrum: playback.spectrum,
                kind: visualizerKind,
                lineColor: Color(hex: lineColorHex),
                onTap: {
                    Haptics.select()
                    visualizer = visualizerKind.next.rawValue
                }
            )
        }
    }

    // MARK: - Перемотка

    private var progress: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isDragging ? dragValue : engine.currentTime },
                    set: { dragValue = $0 }
                ),
                in: 0...max(engine.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        dragValue = engine.currentTime
                        isDragging = true
                    } else {
                        // Перемотка — только при отпускании
                        playback.seek(to: dragValue)
                        isDragging = false
                    }
                }
            )
            .tint(palette.accent)
            .disabled(!engine.isLoaded)
            .accessibilityLabel(tr("Позиция воспроизведения"))

            HStack {
                Text(TimeText.format(isDragging ? dragValue : engine.currentTime))
                Spacer()
                Text(TimeText.format(engine.duration))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(palette.secondaryText)
        }
    }

    // MARK: - Основной ряд

    private var mainControls: some View {
        HStack(spacing: 0) {
            roundButton(
                systemImage: "shuffle",
                size: 40 * big,
                foreground: playback.shuffleOn ? palette.accent : palette.secondaryText,
                background: playback.shuffleOn ? palette.rowCurrent : .clear,
                label: playback.shuffleOn ? tr("Честный рандом включён") : tr("Честный рандом выключен")
            ) {
                playback.toggleShuffle()
            }
            Spacer(minLength: 0)
            roundButton(systemImage: "backward.end.fill", size: 48 * big, foreground: palette.text, background: palette.button, label: tr("Предыдущий трек")) {
                playback.previous()
            }
            .disabled(!hasTrack)
            Spacer(minLength: 0)
            skipButton(forward: false)
            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                playback.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30 * big, weight: .bold))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 72 * big, height: 72 * big)
                    .background(Circle().fill(palette.accent))
                    .shadow(color: palette.accent.opacity(0.35), radius: 9, y: 4)
            }
            .buttonStyle(PressDarkenStyle())
            .disabled(!hasTrack)
            .accessibilityLabel(engine.isPlaying ? tr("Пауза") : tr("Играть"))

            Spacer(minLength: 0)
            skipButton(forward: true)
            Spacer(minLength: 0)
            roundButton(systemImage: "forward.end.fill", size: 48 * big, foreground: palette.text, background: palette.button, label: tr("Следующий трек")) {
                playback.next()
            }
            .disabled(!hasTrack)
            Spacer(minLength: 0)
            roundButton(
                systemImage: playback.repeatMode == .one ? "repeat.1" : "repeat",
                size: 40 * big,
                foreground: playback.repeatMode == .off ? palette.secondaryText : palette.accent,
                background: playback.repeatMode == .off ? .clear : palette.rowCurrent,
                label: repeatLabel
            ) {
                playback.cycleRepeat()
            }
        }
    }

    private var repeatLabel: String {
        switch playback.repeatMode {
        case .off: return tr("Повтор выключен")
        case .all: return tr("Повтор всего списка")
        case .one: return tr("Повтор одного трека")
        }
    }

    private func roundButton(
        systemImage: String,
        size: CGFloat,
        foreground: Color,
        background: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
        }
        .buttonStyle(PressDarkenStyle())
        .accessibilityLabel(label)
    }

    private func skipButton(forward: Bool) -> some View {
        Button {
            if forward {
                playback.skipForward()
            } else {
                playback.skipBackward()
            }
        } label: {
            VStack(spacing: -2) {
                Image(systemName: forward ? "arrow.clockwise" : "arrow.counterclockwise")
                    .font(.system(size: 19 * big, weight: .semibold))
                Text("\(skipInterval)")
                    .font(.system(size: 10 * big, weight: .bold))
            }
            .foregroundStyle(palette.text)
            .frame(width: 40 * big, height: 48 * big)
        }
        .buttonStyle(PressDarkenStyle())
        .disabled(!hasTrack)
        .accessibilityLabel(forward ? tr("Вперёд на %@ секунд", "\(skipInterval)") : tr("Назад на %@ секунд", "\(skipInterval)"))
    }

    // MARK: - Второй ряд

    private var secondaryControls: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(PlaybackSpeed.all, id: \.self) { rate in
                    Button(PlaybackSpeed.label(rate)) {
                        playback.setRate(rate)
                    }
                }
            } label: {
                Text(PlaybackSpeed.label(engine.rate))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .frame(minWidth: 52, minHeight: 36)
                    .padding(.horizontal, 6)
                    .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            } primaryAction: {
                playback.setRate(PlaybackSpeed.next(after: engine.rate))
            }
            .accessibilityLabel(tr("Скорость %@", "\(PlaybackSpeed.label(engine.rate))"))

            Spacer(minLength: 0)
            iconButton("slider.vertical.3", label: tr("Эквалайзер"), action: onEqualizer)
            Spacer(minLength: 0)
            Menu {
                Button {
                    onBookmark()
                } label: {
                    Label(tr("Добавить закладку"), systemImage: "bookmark")
                }
                .disabled(!hasTrack)
                Button {
                    onBookmarksList()
                } label: {
                    Label(tr("Все закладки"), systemImage: "list.bullet")
                }
            } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 44, height: 44)
            } primaryAction: {
                if hasTrack {
                    onBookmark()
                } else {
                    onBookmarksList()
                }
            }
            .accessibilityLabel(tr("Закладка: нажмите — добавить, удерживайте — список"))
            Spacer(minLength: 0)
            sleepButton
            if !playback.chapters.isEmpty {
                Spacer(minLength: 0)
                iconButton("list.number", label: tr("Главы"), action: onChapters)
            }
            Spacer(minLength: 0)
            iconButton(RecognizeIcon.name, label: tr("Распознать песню"), action: onRecognize)
            Spacer(minLength: 0)
            iconButton("plus.circle", label: tr("Добавить файлы"), action: onImport)
            Spacer(minLength: 0)
            iconButton("gearshape", label: tr("Настройки"), action: onSettings)
        }
    }

    /// Луна таймера сна; при работающем таймере — оставшееся время.
    private var sleepButton: some View {
        Button(action: onSleepTimer) {
            VStack(spacing: 0) {
                Image(systemName: playback.sleepTimer.isActive ? "moon.fill" : "moon")
                    .font(.system(size: 18))
                    .foregroundStyle(playback.sleepTimer.isActive ? palette.accent : palette.secondaryText)
                if playback.sleepTimer.isActive {
                    Text(sleepLabel)
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.accent)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(PressDarkenStyle())
        .accessibilityLabel(playback.sleepTimer.isActive ? tr("Таймер сна: %@", "\(sleepLabel)") : tr("Таймер сна"))
    }

    private var sleepLabel: String {
        switch playback.sleepTimer.mode {
        case .endOfTrack: return tr("трек")
        case .until:
            let seconds = Int(playback.sleepTimer.remaining.rounded(.up))
            return seconds >= 3600
                ? String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
                : String(format: "%d:%02d", seconds / 60, seconds % 60)
        case .off: return ""
        }
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PressDarkenStyle())
        .accessibilityLabel(label)
    }
}

/// ЖК-дисплей в стиле классических плееров (скин «Классика»).
/// Нажатие переключает вид визуализатора.
struct LCDDisplay: View {
    let track: TrackRecord?
    let rowNumber: Int?
    let time: Double
    let isPlaying: Bool
    let chapterTitle: String?
    let spectrum: SpectrumAnalyzer
    let kind: VisualizerKind
    let lineColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(rowNumber.map { String(format: "%02d.", $0) } ?? "--.")
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(Palette.lcdDim)
                        Text(TimeText.format(time))
                            .font(.system(size: 34, weight: .regular, design: .monospaced))
                            .foregroundStyle(Palette.lcdText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatLine)
                        Text(kind.lcdName)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.lcdDim)
                }
                Text(titleLine)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Palette.lcdText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let chapterTitle {
                    Text(tr("ГЛАВА: ") + chapterTitle)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.lcdDim)
                        .lineLimit(1)
                }
                VisualizerView(spectrum: spectrum, kind: kind, isPlaying: isPlaying, lineColor: lineColor)
                    .frame(height: kind == .needles ? 60 : 32)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.lcdBackground))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.lcdBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(tr("Нажмите, чтобы сменить визуализатор"))
    }

    private var titleLine: String {
        guard let track else { return "PLAYMYDISK" }
        let artist = track.artist.isEmpty ? "" : track.artist + " — "
        return artist + track.displayTitle
    }

    private var formatLine: String {
        guard let track else { return "" }
        if track.bitrateKbps > 0 {
            return "\(track.formatName) · \(track.bitrateKbps) KBPS"
        }
        return track.formatName
    }
}

/// Обложка трека из кэша (nil — обложки нет).
@MainActor
func artworkImage(for track: TrackRecord?) -> UIImage? {
    guard let track, track.hasArtwork else { return nil }
    return UIImage(contentsOfFile: ArtworkCache.url(for: track.uid, thumbnail: false).path)
}

/// Скин Minimalist Modern: размытая обложка на фоне, круглая обложка
/// с радиальным спектром вокруг.
struct ModernDisplay: View {
    let playback: PlaybackController
    let time: Double

    @Environment(\.palette) private var palette

    var body: some View {
        let image = artworkImage(for: playback.currentTrack)
        HStack(spacing: 16) {
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playback.isPlaying)) { _ in
                    RadialSpectrum(
                        bands: playback.isPlaying ? playback.spectrum.snapshot().bands : Array(repeating: 0, count: SpectrumAnalyzer.bandCount),
                        color: palette.accent,
                        innerRadius: 44
                    )
                }
                artwork(image)
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
            }
            .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: 6) {
                Text(playback.currentTrack?.displayTitle ?? "PlayMyDisk")
                    .font(.headline)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                Text(playback.currentTrack?.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                if let chapter = playback.currentChapter {
                    Text(chapter.title)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Text(TimeText.format(time))
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 30)
                        .opacity(0.45)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func artwork(_ image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Circle().fill(palette.button)
                Image(systemName: "music.note")
                    .font(.system(size: 30))
                    .foregroundStyle(palette.accent)
            }
        }
    }
}

/// Скин Retro: кассета с крутящимися катушками или пластинка + стрелочные приборы.
struct RetroDisplay: View {
    let playback: PlaybackController
    let time: Double
    let vinyl: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playback.isPlaying)) { context in
                // Угол поворота зависит от времени и скорости воспроизведения
                let seconds = context.date.timeIntervalSinceReferenceDate
                let angle = Angle.radians(playback.isPlaying ? seconds * 2.2 * Double(playback.engine.rate) : 0)
                if vinyl {
                    HStack(spacing: 14) {
                        VinylDisc(angle: angle, accent: palette.accent)
                            .frame(width: 110, height: 110)
                        labelBlock
                    }
                } else {
                    VStack(spacing: 6) {
                        HStack(spacing: 40) {
                            CassetteReel(angle: angle).frame(width: 54, height: 54)
                            CassetteReel(angle: angle).frame(width: 54, height: 54)
                        }
                        labelBlock
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#3A2A1A")))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#5A3A1C"), lineWidth: 2))
                }
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playback.isPlaying)) { _ in
                let snapshot = playback.isPlaying ? playback.spectrum.snapshot() : SpectrumAnalyzer.Snapshot(bands: [], left: 0, right: 0)
                HStack(spacing: 10) {
                    VUMeter(level: snapshot.left, label: "L")
                    VUMeter(level: snapshot.right, label: "R")
                }
                .frame(height: 56)
            }
        }
    }

    private var labelBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(playback.currentTrack?.displayTitle ?? "PlayMyDisk")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .lineLimit(1)
            Text(playback.currentTrack?.artist ?? "")
                .font(.system(size: 13, design: .serif))
                .lineLimit(1)
            Text(TimeText.format(time))
                .font(.system(size: 13, design: .monospaced))
        }
        .foregroundStyle(Color(hex: "#1A0E00"))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#F3E3C3")))
    }
}

/// Скин Car Mode: крупное время и название, без мелких деталей.
struct CarDisplay: View {
    let playback: PlaybackController
    let rowNumber: Int?
    let time: Double

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(TimeText.format(time))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
                Spacer()
                if let rowNumber {
                    Text("№ \(rowNumber)")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                }
            }
            Text(playback.currentTrack?.displayTitle ?? "PlayMyDisk")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(playback.currentTrack?.artist ?? "")
                .font(.system(size: 20))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.button))
    }
}
