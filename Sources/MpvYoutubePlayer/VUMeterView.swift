import SwiftUI

/// Vúmetro estéreo mostrado durante la reproducción en modo solo audio,
/// entre la barra de controles y el título. Un clic alterna entre el estilo
/// digital (tiras LED) y el analógico (agujas), recordado en
/// `VUMeterSettingsManager`.
struct VUMeterView: View {
    let leftLevel: Double
    let rightLevel: Double

    @ObservedObject private var settings = VUMeterSettingsManager.shared

    var body: some View {
        Group {
            switch settings.style {
            case .digital:
                DigitalVUMeterView(leftLevel: leftLevel, rightLevel: rightLevel)
            case .analog:
                AnalogVUMeterView(leftLevel: leftLevel, rightLevel: rightLevel)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { settings.toggle() }
        .help(LocalizationManager.shared.t(.vuMeterToggleTooltip))
    }
}

// MARK: - Digital (tiras LED)

private struct DigitalVUMeterView: View {
    let leftLevel: Double
    let rightLevel: Double

    var body: some View {
        VStack(spacing: 4) {
            LEDStripRow(level: leftLevel)
            LEDStripRow(level: rightLevel)
        }
    }
}

private struct LEDStripRow: View {
    let level: Double
    private let segmentCount = 24

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(for: index))
                    .opacity(isLit(index) ? 1 : 0.15)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.15), value: level)
    }

    private func isLit(_ index: Int) -> Bool {
        Double(index) / Double(segmentCount) < level
    }

    /// Igual degradado verde→ámbar→rojo que un vúmetro de hardware clásico:
    /// el rojo marca la zona cercana al clipping, no un nivel "malo" en sí.
    private func color(for index: Int) -> Color {
        let position = Double(index) / Double(segmentCount)
        if position < 0.7 { return .green }
        if position < 0.9 { return Color(red: 1, green: 0.75, blue: 0) }
        return .red
    }
}

// MARK: - Analógico (dos relojes de aguja)

private struct AnalogVUMeterView: View {
    let leftLevel: Double
    let rightLevel: Double

    /// Cada reloj es un cuadrado; el widget completo (los dos uno junto al
    /// otro) queda entonces rectangular en horizontal, nunca en vertical -
    /// antes cada reloj heredaba el alto completo del contenedor y quedaba
    /// muy alto y estrecho, con mucho hueco vacío por encima de la esfera.
    private static let gaugeSize: CGFloat = 76

    var body: some View {
        HStack(spacing: 6) {
            AnalogNeedleGauge(level: leftLevel, label: "L")
                .frame(width: Self.gaugeSize, height: Self.gaugeSize)
            AnalogNeedleGauge(level: rightLevel, label: "R")
                .frame(width: Self.gaugeSize, height: Self.gaugeSize)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AnalogNeedleGauge: View {
    let level: Double
    let label: String

    /// Barrido de la aguja en grados, con 0° apuntando hacia arriba (12 en
    /// punto) y positivo hacia la derecha, como las agujas de un reloj.
    fileprivate static let minAngle = -50.0
    fileprivate static let maxAngle = 50.0
    fileprivate static let redZoneStartAngle = 25.0

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let pivot = CGPoint(x: rect.midX, y: rect.maxY - 14)
            let radius = Self.radius(for: rect)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                GaugeFaceShape(pivot: pivot, radius: radius)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1.5)
                GaugeFaceShape(
                    pivot: pivot,
                    radius: radius,
                    startAngle: Self.redZoneStartAngle,
                    endAngle: Self.maxAngle
                )
                .stroke(Color.red.opacity(0.7), lineWidth: 2.5)

                ForEach(Self.tickAngles, id: \.self) { degrees in
                    TickMark(angleDegrees: degrees, pivot: pivot, radius: radius)
                }

                NeedleShape(level: level.clamped(0...1), pivot: pivot, radius: radius * 0.88)
                    .stroke(Color.primary, lineWidth: 1.5)
                    .animation(.easeOut(duration: 0.25), value: level)

                Circle()
                    .fill(Color.primary)
                    .frame(width: 5, height: 5)
                    .position(pivot)

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: pivot.x, y: rect.maxY - 4)
            }
        }
    }

    private static let tickAngles: [Double] = [-50, -25, 0, 25, 50]

    private static func radius(for rect: CGRect) -> CGFloat {
        min(rect.width, rect.height * 1.6) / 2 - 6
    }
}

private struct TickMark: View {
    let angleDegrees: Double
    let pivot: CGPoint
    let radius: CGFloat

    var body: some View {
        let angle = Angle.degrees(angleDegrees).radians
        let outer = CGPoint(x: pivot.x + radius * sin(angle), y: pivot.y - radius * cos(angle))
        let inner = CGPoint(x: pivot.x + (radius - 5) * sin(angle), y: pivot.y - (radius - 5) * cos(angle))
        Path { path in
            path.move(to: inner)
            path.addLine(to: outer)
        }
        .stroke(angleDegrees >= 25 ? Color.red.opacity(0.7) : Color.secondary, lineWidth: 1)
    }
}

/// Escala de fondo del reloj, como un arco trazado punto a punto en vez de
/// con `Path.addArc` para compartir la misma convención de ángulos
/// (0°=arriba, positivo=hacia la derecha) que `NeedleShape` y `TickMark`.
private struct GaugeFaceShape: Shape {
    let pivot: CGPoint
    let radius: CGFloat
    var startAngle: Double = AnalogNeedleGauge.minAngle
    var endAngle: Double = AnalogNeedleGauge.maxAngle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 24
        for i in 0...steps {
            let degrees = startAngle + (endAngle - startAngle) * Double(i) / Double(steps)
            let radians = Angle.degrees(degrees).radians
            let point = CGPoint(x: pivot.x + radius * sin(radians), y: pivot.y - radius * cos(radians))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// La aguja en sí: `Shape` (no `Canvas`) para que `.animation(value:)` la
/// anime de verdad interpolando `level` fotograma a fotograma vía
/// `animatableData`, en vez de saltar de golpe entre valores.
private struct NeedleShape: Shape {
    var level: Double
    let pivot: CGPoint
    let radius: CGFloat

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let degrees = AnalogNeedleGauge.minAngle + (AnalogNeedleGauge.maxAngle - AnalogNeedleGauge.minAngle) * level
        let radians = Angle.degrees(degrees).radians
        let tip = CGPoint(x: pivot.x + radius * sin(radians), y: pivot.y - radius * cos(radians))
        var path = Path()
        path.move(to: pivot)
        path.addLine(to: tip)
        return path
    }
}

private extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
