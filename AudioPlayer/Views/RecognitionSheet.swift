import SwiftUI
import UIKit

/// Экран распознавания: «Слушаю…», результат, «не найдено» или запасной вариант.
struct RecognitionSheet: View {
    let controller: RecognitionController

    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 18) {
            content
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(palette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .idle:
            EmptyView()

        case .listening:
            Image(systemName: RecognizeIcon.name)
                .font(.system(size: 64))
                .foregroundStyle(palette.accent)
                .symbolEffect(.pulse, options: .repeating)
                .padding(.top, 12)
            Text("Слушаю…")
                .font(.title2.bold())
                .foregroundStyle(palette.text)
            Text("Поднесите iPhone ближе к источнику звука. До 15 секунд.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.secondaryText)
            closeButton("Отмена")

        case .found(let song):
            AsyncImage(url: song.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(palette.secondaryText)
            }
            .frame(width: 160, height: 160)
            .background(palette.secondaryText.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(spacing: 4) {
                Text(song.title)
                    .font(.title3.bold())
                    .foregroundStyle(palette.text)
                if !song.artist.isEmpty {
                    Text(song.artist)
                        .font(.body)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .multilineTextAlignment(.center)
            .textSelection(.enabled)
            actionButton("Найти в интернете", systemImage: "magnifyingglass") {
                let query = song.artist.isEmpty ? song.title : "\(song.artist) \(song.title)"
                if let url = AppSettings.searchURL(for: query) {
                    openURL(url)
                }
            }
            if let url = song.appleMusicURL {
                actionButton("Открыть в Apple Music", systemImage: "music.note") {
                    openURL(url)
                }
            }
            closeButton("Закрыть")

        case .notFound:
            Image(systemName: "questionmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 12)
            Text("Не удалось распознать")
                .font(.title3.bold())
                .foregroundStyle(palette.text)
            Text("Попробуйте ещё раз, когда музыка играет громче и без помех.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.secondaryText)
            actionButton("Ещё раз", systemImage: "arrow.clockwise") {
                controller.retry()
            }
            closeButton("Закрыть")

        case .micDenied:
            Image(systemName: "mic.slash")
                .font(.system(size: 56))
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 12)
            Text("Нет доступа к микрофону")
                .font(.title3.bold())
                .foregroundStyle(palette.text)
            Text("Разрешите доступ в Настройках iPhone → PlayMyDisk → Микрофон.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.secondaryText)
            actionButton("Открыть Настройки", systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            closeButton("Закрыть")

        case .unavailable(let openedShazam):
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 52))
                .foregroundStyle(palette.accent)
                .padding(.top, 12)
            Text("Распознавание в плеере недоступно")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.text)
            if openedShazam {
                Text("Открыл приложение Shazam. Когда вернётесь — нажмите «Закрыть», и музыка продолжит играть.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.secondaryText)
            } else {
                Text("Используйте «Распознавание музыки» в Пункте управления. Если кнопки там нет: Настройки iPhone → Пункт управления → добавьте «Распознавание музыки».")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.secondaryText)
            }
            Text("Подробности — в Журнале отладки.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
            closeButton("Закрыть")
        }
    }

    private func actionButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(palette.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(palette.text)
        }
        .buttonStyle(PressDarkenStyle())
    }

    private func closeButton(_ title: LocalizedStringKey) -> some View {
        Button {
            Haptics.tap()
            controller.close()
        } label: {
            Text(title)
                .font(.body)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(palette.secondaryText)
        }
        .buttonStyle(PressDarkenStyle())
    }
}

/// Значок кнопки «Распознать»: логотип Shazam из SF Symbols, если он есть в системе.
enum RecognizeIcon {
    static let name: String = UIImage(systemName: "shazam.logo") != nil ? "shazam.logo" : "waveform.and.magnifyingglass"
}
