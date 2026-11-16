import SwiftUI

/// Строка списка: одна строка экрана (трек или строка плейлиста).
struct ListRowItem: Identifiable {
    /// Для плейлиста — ID строки плейлиста (трек может стоять дважды), иначе — ID трека.
    let id: UUID
    let track: TrackRecord
    let entry: PlaylistEntry?
    /// Номер строки, с единицы.
    let number: Int
}

/// Строка трека: номер · название и исполнитель · ♥ · время и прослушивания · ⚙.
/// Сердечко и шестерёнка разнесены по разные стороны от времени, чтобы не промахнуться.
struct TrackRow: View {
    let item: ListRowItem
    let isCurrent: Bool
    let isPlaying: Bool
    let showHeart: Bool
    let showPlayCount: Bool
    let onPlay: () -> Void
    let onToggleSuper: () -> Void
    let onMenu: () -> Void

    @Environment(\.palette) private var palette

    private var track: TrackRecord { item.track }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    number
                        .frame(width: 32, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.displayTitle)
                            .font(.system(size: 15, weight: isCurrent ? .bold : .medium))
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if track.isProtected {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                    .accessibilityLabel("Защищённый файл")
                            }
                            Text(track.artist.isEmpty ? "Неизвестный исполнитель" : track.artist)
                                .lineLimit(1)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.number). \(track.artist) — \(track.displayTitle)")

            if showHeart {
                Button {
                    Haptics.select()
                    onToggleSuper()
                } label: {
                    Image(systemName: track.isSuper ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundStyle(track.isSuper ? Palette.heart : palette.secondaryText)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(track.isSuper ? "Убрать из «Супер!»" : "Супер!")
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(TimeText.format(track.duration))
                    .font(.system(size: 13))
                if showPlayCount {
                    HStack(spacing: 2) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 7))
                        Text("\(track.playCount)")
                    }
                    .font(.system(size: 11))
                    .accessibilityLabel("Прослушиваний: \(track.playCount)")
                }
            }
            .monospacedDigit()
            .foregroundStyle(palette.secondaryText)
            .frame(width: 46, alignment: .trailing)

            Button {
                Haptics.tap()
                onMenu()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Действия с файлом «\(track.displayTitle)»")
        }
        .frame(height: 56)
    }

    @ViewBuilder
    private var number: some View {
        if isCurrent {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 15))
                .foregroundStyle(palette.accent)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                .accessibilityLabel("Играет")
        } else {
            Text(String(format: "%02d", item.number))
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
        }
    }
}
