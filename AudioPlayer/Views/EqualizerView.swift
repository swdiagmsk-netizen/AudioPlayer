import SwiftUI

/// Экран эквалайзера: вкл/выкл, пресеты, 10 полос, предусилитель, свои пресеты.
struct EqualizerView: View {
    let equalizer: EqualizerManager

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var showSave = false
    @State private var saveName = ""

    private let labels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    presets
                    bands
                    preamp
                    buttons
                    Text(tr("Ручные настройки и свои пресеты сохраняются автоматически."))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
                .opacity(equalizer.isEnabled ? 1 : 0.45)
            }
            .background(palette.background)
            .navigationTitle(tr("Эквалайзер"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Готово")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Toggle(tr("Эквалайзер включён"), isOn: Binding(
                        get: { equalizer.isEnabled },
                        set: { equalizer.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .tint(palette.accent)
                }
            }
            .alert(tr("Сохранить пресет"), isPresented: $showSave) {
                TextField(tr("Название"), text: $saveName)
                Button(tr("Сохранить")) {
                    equalizer.saveCurrent(as: saveName)
                    saveName = ""
                }
                Button(tr("Отмена"), role: .cancel) {
                    saveName = ""
                }
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("ПРЕСЕТЫ"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Button(tr("+ Сохранить как свой")) {
                    showSave = true
                }
                .font(.footnote.weight(.semibold))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(equalizer.allPresets) { preset in
                        let isOn = preset.name == equalizer.presetName
                        Button {
                            equalizer.select(preset)
                        } label: {
                            Text(tr(preset.name))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isOn ? palette.onAccent : palette.text)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 34)
                                .background(Capsule().fill(isOn ? palette.accent : palette.button))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var bands: some View {
        VStack(spacing: 6) {
            HStack {
                Text(tr("+12 дБ"))
                Spacer()
                Text(tr(equalizer.presetName).uppercased())
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.lcdDim)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<10, id: \.self) { index in
                    VStack(spacing: 6) {
                        Text(format(equalizer.gains[index]))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.lcdText)
                        // Вертикальный ползунок: обычный, повёрнутый на 90°
                        Slider(
                            value: Binding(
                                get: { Double(equalizer.gains[index]) },
                                set: { equalizer.setGain(Float(($0 * 2).rounded() / 2), band: index) }
                            ),
                            in: -12...12
                        )
                        .tint(palette.accent)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 180)
                        .frame(width: 30, height: 180)
                        .accessibilityLabel(tr("Полоса %@ герц", "\(labels[index])"))
                        .accessibilityValue(tr("%@ децибел", "\(format(equalizer.gains[index]))"))
                        Text(labels[index])
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack {
                Text(tr("−12 дБ"))
                Spacer()
                Text(tr("Гц"))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.lcdDim)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.lcdBackground))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.lcdBorder, lineWidth: 1))
    }

    private var preamp: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("Предусилитель"))
                    .foregroundStyle(palette.text)
                Spacer()
                Text(tr("%@ дБ", "\(format(equalizer.preamp))"))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondaryText)
            }
            Slider(
                value: Binding(
                    get: { Double(equalizer.preamp) },
                    set: { equalizer.setPreamp(Float(($0 * 2).rounded() / 2)) }
                ),
                in: -12...6
            )
            .tint(palette.accent)
            .accessibilityLabel(tr("Предусилитель"))
            Text(tr("Если поднимаете много полос — убавьте предусилитель, чтобы не было хрипа."))
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.panel))
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button(tr("Сбросить (Flat)")) {
                equalizer.resetFlat()
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).stroke(palette.line))

            Button(tr("Удалить свой пресет")) {
                equalizer.deleteCurrentUserPreset()
            }
            .foregroundStyle(equalizer.currentPresetIsUser ? Palette.danger : palette.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).stroke(palette.line))
            .disabled(!equalizer.currentPresetIsUser)
        }
        .font(.subheadline.weight(.semibold))
    }

    private func format(_ value: Float) -> String {
        let rounded = (value * 2).rounded() / 2
        let text = rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
        return rounded > 0 ? "+" + text : text
    }
}
