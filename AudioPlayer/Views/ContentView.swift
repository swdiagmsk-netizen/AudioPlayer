import SwiftUI
import UniformTypeIdentifiers

/// Экран этапа 0: выбрать файл и проиграть его.
struct ContentView: View {
    @State private var player = SimplePlayer()
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

            Text(player.title)
                .font(.title3)
                .multilineTextAlignment(.center)

            Text(player.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showImporter = true
            } label: {
                Label("Выбрать файл", systemImage: "plus.circle.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                player.togglePlayPause()
            } label: {
                Label(player.isPlaying ? "Пауза" : "Играть",
                      systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!player.hasFile)

            Text("Скелет 0.1.0 — проверка сборки и установки")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [UTType.audio],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    player.importAndPlay(from: url)
                }
            case .failure(let error):
                player.status = "Ошибка выбора: \(error.localizedDescription)"
            }
        }
    }
}
