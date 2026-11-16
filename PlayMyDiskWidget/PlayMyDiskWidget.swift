import AppIntents
import SwiftUI
import WidgetKit

/// Расширение с кнопкой «Распознать» для экрана блокировки и Пункта управления.
@main
struct PlayMyDiskWidgets: WidgetBundle {
    var body: some Widget {
        RecognizeSongControl()
    }
}

struct RecognizeSongControl: ControlWidget {
    static let kind = "com.local.audioplayer.recognize"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: RecognizeSongIntent()) {
                Label("Распознать", systemImage: "shazam.logo")
            }
        }
        .displayName("Распознать песню")
        .description("Открывает PlayMyDisk и слушает, что играет рядом.")
    }
}
