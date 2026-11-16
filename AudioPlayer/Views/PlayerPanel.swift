import SwiftUI

/// Верхняя панель плеера: ЖК-дисплей, перемотка, кнопки управления.
struct PlayerPanel: View {
    let playback: PlaybackController
    /// Номер строки играющего трека в открытом списке (nil — трек не из этого списка).
    let currentRowNumber: Int?
    let onImport: () -> Void
    let onSettings: () -> Void
    let onBookmark: () -> Void

    @Environment(\.palette) private var palette
    @AppStorage(SettingsKeys.skipInterval) private var skipInterval: Int = 15

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    private var engine: AudioEngineManager { playback.engine }
    private var hasTrack: Bool { playback.currentTrack != nil }

    var body: some View {
        VStack(spacing: 12) {
            LCDDisplay(
                track: playback.currentTrack,
                rowNumber: currentRowNumber,
                time: isDragging ? dragValue : engine.currentTime,
                isPlaying: engine.isPlaying
            )
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
            .accessibilityLabel("Позиция воспроизведения")

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
                size: 40,
                foreground: playback.shuffleOn ? palette.accent : palette.secondaryText,
                background: playback.shuffleOn ? palette.rowCurrent : .clear,
                label: playback.shuffleOn ? "Честный рандом включён" : "Честный рандом выключен"
            ) {
                playback.toggleShuffle()
            }
            Spacer(minLength: 0)
            roundButton(systemImage: "backward.end.fill", size: 48, foreground: palette.text, background: palette.button, label: "Предыдущий трек") {
                playback.previous()
            }
            .disabled(!hasTrack)
            Spacer(minLength: 0)
            skipButton(forward: false)
            Spacer(minLength: 0)

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(palette.accent))
                    .shadow(color: palette.accent.opacity(0.35), radius: 9, y: 4)
            }
            .buttonStyle(PressDarkenStyle())
            .disabled(!hasTrack)
            .accessibilityLabel(engine.isPlaying ? "Пауза" : "Играть")

            Spacer(minLength: 0)
            skipButton(forward: true)
            Spacer(minLength: 0)
            roundButton(systemImage: "forward.end.fill", size: 48, foreground: palette.text, background: palette.button, label: "Следующий трек") {
                playback.next()
            }
            .disabled(!hasTrack)
            Spacer(minLength: 0)
            roundButton(
                systemImage: playback.repeatMode == .one ? "repeat.1" : "repeat",
                size: 40,
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
        case .off: return "Повтор выключен"
        case .all: return "Повтор всего списка"
        case .one: return "Повтор одного трека"
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
        Button(action: action) {
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
                    .font(.system(size: 19, weight: .semibold))
                Text("\(skipInterval)")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(palette.text)
            .frame(width: 40, height: 48)
        }
        .buttonStyle(PressDarkenStyle())
        .disabled(!hasTrack)
        .accessibilityLabel(forward ? "Вперёд на \(skipInterval) секунд" : "Назад на \(skipInterval) секунд")
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
            .accessibilityLabel("Скорость \(PlaybackSpeed.label(engine.rate))")

            Spacer(minLength: 0)
            iconButton("bookmark", label: "Добавить закладку", action: onBookmark)
                .disabled(!hasTrack)
            Spacer(minLength: 0)
            iconButton("plus.circle", label: "Добавить файлы", action: onImport)
            Spacer(minLength: 0)
            iconButton("gearshape", label: "Настройки", action: onSettings)
        }
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PressDarkenStyle())
        .accessibilityLabel(label)
    }
}

/// ЖК-дисплей в стиле классических плееров.
struct LCDDisplay: View {
    let track: TrackRecord?
    let rowNumber: Int?
    let time: Double
    let isPlaying: Bool

    var body: some View {
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
                    Text(sampleLine)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.lcdDim)
            }
            Text(titleLine)
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Palette.lcdText)
                .lineLimit(1)
                .truncationMode(.tail)
            SpectrumPlaceholder(isPlaying: isPlaying)
                .frame(height: 30)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.lcdBackground))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.lcdBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
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

    private var sampleLine: String {
        guard let track, track.sampleRate > 0 else { return "" }
        let khz = track.sampleRate / 1000
        let text = khz.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
        return "\(text) KHZ"
    }
}

/// Анимированные столбики на дисплее. На этапе 6 их заменит настоящий
/// спектр (FFT) с выбором вида: столбики, стрелки, тонкие линии.
struct SpectrumPlaceholder: View {
    let isPlaying: Bool
    private let bars = 28

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<bars, id: \.self) { i in
                        let wave = abs(sin(t * 3.1 + Double(i) * 1.7) * cos(t * 1.3 + Double(i) * 0.4))
                        let level = isPlaying ? 0.15 + 0.85 * wave : 0.06
                        RoundedRectangle(cornerRadius: 1)
                            .fill(LinearGradient(
                                colors: [Color(hex: "#FFD23F"), Palette.lcdText, Color(hex: "#2E9E3E")],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(height: max(2, geo.size.height * level))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}
