import SwiftUI

/// Вид визуализатора.
enum VisualizerKind: String, CaseIterable {
    case bars, needles, lines

    var title: String {
        switch self {
        case .bars: return "Столбики"
        case .needles: return "Стрелки"
        case .lines: return "Линии"
        }
    }

    var lcdName: String {
        switch self {
        case .bars: return "СТОЛБИКИ"
        case .needles: return "СТРЕЛКИ VU"
        case .lines: return "ЛИНИИ"
        }
    }

    var next: VisualizerKind {
        switch self {
        case .bars: return .needles
        case .needles: return .lines
        case .lines: return .bars
        }
    }
}

/// Визуализатор на дисплее: читает спектр ~30 раз в секунду, пока играет музыка.
struct VisualizerView: View {
    let spectrum: SpectrumAnalyzer
    let kind: VisualizerKind
    let isPlaying: Bool
    let lineColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { _ in
            let snapshot = isPlaying ? spectrum.snapshot() : SpectrumAnalyzer.Snapshot(
                bands: Array(repeating: 0, count: SpectrumAnalyzer.bandCount), left: 0, right: 0
            )
            switch kind {
            case .bars:
                BarsVisualizer(bands: snapshot.bands)
            case .needles:
                HStack(spacing: 10) {
                    VUMeter(level: snapshot.left, label: "L")
                    VUMeter(level: snapshot.right, label: "R")
                }
            case .lines:
                LinesVisualizer(bands: snapshot.bands, color: lineColor)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 28 столбиков (полосы спектра попарно) с зелёно-жёлтым градиентом.
struct BarsVisualizer: View {
    let bands: [Float]

    var body: some View {
        Canvas { context, size in
            let count = 28
            let gap: CGFloat = 3
            let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            let gradient = Gradient(colors: [Color(hex: "#FFD23F"), Palette.lcdText, Color(hex: "#2E9E3E")])
            for i in 0..<count {
                let a = bands.indices.contains(i * 2) ? bands[i * 2] : 0
                let b = bands.indices.contains(i * 2 + 1) ? bands[i * 2 + 1] : 0
                let level = CGFloat(max(a, b))
                let height = max(2, size.height * level)
                let rect = CGRect(x: CGFloat(i) * (width + gap), y: size.height - height, width: width, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height))
                )
            }
        }
    }
}

/// 56 сверхтонких линий с градиентом «цвет → прозрачный».
struct LinesVisualizer: View {
    let bands: [Float]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let count = bands.count
            guard count > 1 else { return }
            let step = size.width / CGFloat(count - 1)
            let gradient = Gradient(colors: [color, color.opacity(0.13)])
            for i in 0..<count {
                let height = max(2, size.height * CGFloat(bands[i]))
                let rect = CGRect(x: CGFloat(i) * step - 0.75, y: size.height - height, width: 1.5, height: height)
                context.fill(
                    Path(rect),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                    )
                )
            }
        }
    }
}

/// Стрелочный прибор уровня: шкала −20…+3, красная зона в конце.
struct VUMeter: View {
    let level: Float
    let label: String

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.95)
            let radius = min(size.width / 2 - 6, size.height * 0.85)
            let start = Angle.degrees(-150)
            let end = Angle.degrees(-30)
            let redStart = Angle.degrees(-48)

            var scale = Path()
            scale.addArc(center: center, radius: radius, startAngle: start, endAngle: redStart, clockwise: false)
            context.stroke(scale, with: .color(Palette.lcdText), lineWidth: 2)

            var red = Path()
            red.addArc(center: center, radius: radius, startAngle: redStart, endAngle: end, clockwise: false)
            context.stroke(red, with: .color(Color(hex: "#FF5A3D")), lineWidth: 3)

            // Деления
            for i in 0...6 {
                let angle = Angle.degrees(-150 + Double(i) * 20)
                let outer = CGPoint(x: center.x + cos(angle.radians) * radius, y: center.y + sin(angle.radians) * radius)
                let inner = CGPoint(x: center.x + cos(angle.radians) * (radius - 6), y: center.y + sin(angle.radians) * (radius - 6))
                var tick = Path()
                tick.move(to: inner)
                tick.addLine(to: outer)
                context.stroke(tick, with: .color(Palette.lcdDim), lineWidth: 1.5)
            }

            // Стрелка
            let angle = Angle.degrees(-150 + 120 * Double(min(max(level, 0), 1)))
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: CGPoint(
                x: center.x + cos(angle.radians) * (radius - 2),
                y: center.y + sin(angle.radians) * (radius - 2)
            ))
            context.stroke(needle, with: .color(Color(hex: "#FFD23F")), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(Color(hex: "#FFD23F")))

            context.draw(
                Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.lcdDim),
                at: CGPoint(x: center.x, y: center.y - radius * 0.45)
            )
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: "#0E1610")))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.lcdBorder, lineWidth: 1))
    }
}

/// Радиальный спектр вокруг круглой обложки (скин Minimalist Modern).
struct RadialSpectrum: View {
    let bands: [Float]
    let color: Color
    let innerRadius: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxLength = min(size.width, size.height) / 2 - innerRadius - 2
            let count = bands.count * 2
            for i in 0..<count {
                // Зеркально: полосы идут по кругу туда и обратно
                let bandIndex = i < bands.count ? i : count - 1 - i
                let level = CGFloat(bands[bandIndex])
                let angle = Double(i) / Double(count) * 2 * .pi - .pi / 2
                let length = max(2, maxLength * level)
                let from = CGPoint(x: center.x + cos(angle) * (innerRadius + 3), y: center.y + sin(angle) * (innerRadius + 3))
                let to = CGPoint(x: center.x + cos(angle) * (innerRadius + 3 + length), y: center.y + sin(angle) * (innerRadius + 3 + length))
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(color.opacity(0.4 + 0.6 * Double(level))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Катушка магнитофона; вращается со скоростью воспроизведения.
struct CassetteReel: View {
    let angle: Angle

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(Color(hex: "#2A1A0C")))
            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius * 0.8, y: center.y - radius * 0.8, width: radius * 1.6, height: radius * 1.6)), with: .color(Color(hex: "#5A3A1C")), lineWidth: 2)
            for i in 0..<3 {
                let a = angle.radians + Double(i) * 2 * .pi / 3
                var spoke = Path()
                spoke.move(to: CGPoint(x: center.x + cos(a) * radius * 0.25, y: center.y + sin(a) * radius * 0.25))
                spoke.addLine(to: CGPoint(x: center.x + cos(a) * radius * 0.7, y: center.y + sin(a) * radius * 0.7))
                context.stroke(spoke, with: .color(Color(hex: "#FF8A1F")), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.2, y: center.y - radius * 0.2, width: radius * 0.4, height: radius * 0.4)), with: .color(Color(hex: "#FFD23F")))
        }
        .accessibilityHidden(true)
    }
}

/// Виниловая пластинка с канавками; вращается со скоростью воспроизведения.
struct VinylDisc: View {
    let angle: Angle
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(Color(hex: "#0B0C0E")))
            for ring in stride(from: 0.45, through: 0.95, by: 0.1) {
                let r = radius * ring
                context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(Color(hex: "#1E2126")), lineWidth: 1.5)
            }
            let label = radius * 0.38
            context.fill(Path(ellipseIn: CGRect(x: center.x - label, y: center.y - label, width: label * 2, height: label * 2)), with: .color(accent))
            // Метка на наклейке показывает вращение
            let a = angle.radians
            context.fill(
                Path(ellipseIn: CGRect(x: center.x + cos(a) * label * 0.6 - 3, y: center.y + sin(a) * label * 0.6 - 3, width: 6, height: 6)),
                with: .color(Color(hex: "#1A0E00"))
            )
            context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(Color(hex: "#0B0C0E")))
        }
        .accessibilityHidden(true)
    }
}
