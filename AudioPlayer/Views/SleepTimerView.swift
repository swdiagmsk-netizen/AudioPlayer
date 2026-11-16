import SwiftUI

/// Экран таймера сна: 15/30/45/60 мин, «до конца трека», своё время; затухание.
struct SleepTimerView: View {
    let timer: SleepTimer

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.sleepFadeSeconds) private var fadeSeconds = 15

    /// 0–3 — минуты из списка, 4 — до конца трека, 5 — своё.
    @State private var choice = 1
    @State private var hoursText = "0"
    @State private var minutesText = "20"

    private let presets = [15, 30, 45, 60]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    display
                    options
                    if choice == 5 {
                        customTime
                    }
                    fade
                    actions
                }
                .padding(16)
            }
            .background(palette.background)
            .navigationTitle("Таймер сна")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    // MARK: - Части

    private var display: some View {
        VStack(spacing: 4) {
            Text(timer.isActive ? "ДО ПАУЗЫ ОСТАЛОСЬ" : "ТАЙМЕР ВЫКЛЮЧЕН")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.lcdDim)
            Text(displayText)
                .font(.system(size: 46, design: .monospaced))
                .foregroundStyle(timer.isActive ? Palette.lcdText : Palette.lcdDim)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("ЗАТУХАНИЕ \(fadeSeconds) С")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.lcdDim)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.lcdBackground))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.lcdBorder, lineWidth: 1))
    }

    private var displayText: String {
        switch timer.mode {
        case .endOfTrack:
            return "КОНЕЦ ТРЕКА"
        case .until:
            return clock(Int(timer.remaining.rounded(.up)))
        case .off:
            if choice == 4 { return "КОНЕЦ ТРЕКА" }
            return clock(chosenMinutes * 60)
        }
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    private var chosenMinutes: Int {
        if choice < 4 { return presets[choice] }
        let h = Int(hoursText) ?? 0
        let m = Int(minutesText) ?? 0
        return min(max(h * 60 + m, 1), 720)
    }

    private var options: some View {
        let labels = ["15 мин", "30 мин", "45 мин", "60 мин", "До конца трека", "Своё…"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(labels.indices, id: \.self) { index in
                let isOn = index == choice
                Button {
                    choice = index
                } label: {
                    Text(labels[index])
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(isOn ? palette.accent : palette.text)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(isOn ? palette.rowCurrent : palette.panel))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isOn ? palette.accent : palette.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private var customTime: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Своё время")
                .font(.headline)
                .foregroundStyle(palette.text)
            HStack(spacing: 10) {
                TextField("0", text: $hoursText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.semibold))
                    .frame(width: 64, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(palette.button))
                    .accessibilityLabel("Часы")
                Text("ч").foregroundStyle(palette.secondaryText)
                TextField("0", text: $minutesText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.semibold))
                    .frame(width: 64, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(palette.button))
                    .accessibilityLabel("Минуты")
                Text("мин").foregroundStyle(palette.secondaryText)
            }
            Text("От 1 минуты до 12 часов.")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.panel))
    }

    private var fade: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Плавное затухание перед паузой")
                    .foregroundStyle(palette.text)
                Spacer()
                Text("\(fadeSeconds) с")
                    .monospacedDigit()
                    .foregroundStyle(palette.secondaryText)
            }
            Slider(
                value: Binding(get: { Double(fadeSeconds) }, set: { fadeSeconds = Int($0) }),
                in: 0...60,
                step: 5
            )
            .tint(palette.accent)
            .accessibilityLabel("Длительность затухания")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.panel))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if timer.isActive {
                    timer.cancel()
                } else if choice == 4 {
                    timer.startEndOfTrack()
                } else {
                    timer.start(minutes: chosenMinutes)
                }
            } label: {
                Text(timer.isActive ? "Выключить таймер" : "Запустить таймер")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(timer.isActive ? Palette.danger : palette.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 14).fill(timer.isActive ? palette.button : palette.accent))
            }
            .buttonStyle(PressDarkenStyle())

            if case .until = timer.mode {
                Button {
                    timer.extend()
                } label: {
                    Text("+5 минут")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12).stroke(palette.line))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
