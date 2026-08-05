import SwiftUI

/// Contenido del aviso "reproduciendo ahora": una burbuja translúcida al
/// estilo de una notificación del sistema, no un OSD dibujado por mpv dentro
/// de su propia ventana. El hover para pausar el auto-cierre se detecta a
/// nivel de AppKit (ver `AppDelegate`), no aquí: como esta ventana nunca es
/// la app activa, `.onHover` de SwiftUI no siempre se dispara.
struct TitleToastView: View {
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: 480, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
    }
}
