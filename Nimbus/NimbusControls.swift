import SwiftUI

/// Circular icon control with hover + press feedback (plain ButtonStyle has none on macOS).
struct NimbusCircleIconButton: View {
    let systemName: String
    var help: String = ""
    var role: ButtonRole? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(fill)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(hovering ? 0.14 : 0.08), lineWidth: 0.5)
                )
                .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(NimbusPressableButtonStyle())
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var isDestructive: Bool { role == .destructive }

    private var foreground: Color {
        if isDestructive {
            return hovering ? Color.red.opacity(0.95) : Color.primary.opacity(0.75)
        }
        return Color.primary.opacity(hovering ? 0.95 : 0.8)
    }

    private var fill: Color {
        if isDestructive {
            return Color.red.opacity(hovering ? 0.16 : 0.08)
        }
        return Color.primary.opacity(hovering ? 0.16 : 0.09)
    }
}

/// Text / caption button with hover wash (Clear All, Resume, etc.).
struct NimbusTextButton: View {
    let title: String
    var help: String = ""
    var role: ButtonRole? = nil
    var prominent: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(prominent ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(foreground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(fill)
                )
        }
        .buttonStyle(NimbusPressableButtonStyle())
        .help(help.isEmpty ? title : help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var isDestructive: Bool { role == .destructive }

    private var foreground: Color {
        if isDestructive {
            return hovering ? Color.red : Color.secondary
        }
        return hovering ? Color.primary : Color.secondary
    }

    private var fill: Color {
        if isDestructive {
            return Color.red.opacity(hovering ? 0.14 : 0)
        }
        return Color.primary.opacity(hovering ? 0.10 : 0)
    }
}

/// Filter chip with selected / hover / press states.
struct NimbusFilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected || hovering ? Color.primary : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(background)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(selected ? 0.12 : (hovering ? 0.08 : 0)), lineWidth: 0.5)
                )
        }
        .buttonStyle(NimbusPressableButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: selected)
    }

    private var background: Color {
        if selected {
            return Color.primary.opacity(hovering ? 0.18 : 0.14)
        }
        return Color.primary.opacity(hovering ? 0.10 : 0.05)
    }
}

/// Shared press scale for custom controls.
struct NimbusPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
