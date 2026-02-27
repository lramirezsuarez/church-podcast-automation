import SwiftUI

// MARK: - Brand colours

extension Color {
    static let cpPrimary    = Color(red: 0.22, green: 0.40, blue: 0.82)   // deep blue
    static let cpAccent     = Color(red: 0.95, green: 0.55, blue: 0.18)   // warm orange
    static let cpSurface    = Color(NSColor.controlBackgroundColor)
    static let cpBackground = Color(NSColor.windowBackgroundColor)
}

// MARK: - WizardCard

struct WizardCard<Content: View>: View {
    var title: String
    var subtitle: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2).fontWeight(.semibold)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            content
        }
        .padding(28)
        .background(Color.cpSurface)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.07), radius: 12, x: 0, y: 4)
    }
}

// MARK: - StepProgressRow

struct StepProgressRow: View {
    var step: StepState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusIcon
                Text(step.label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if step.status == .running {
                    Text("\(step.pct)%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cpPrimary)
                }
                if step.status == .done {
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                }
            }

            if step.status == .running {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.cpPrimary.opacity(0.15))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.cpPrimary)
                            .frame(width: geo.size.width * CGFloat(step.pct) / 100, height: 6)
                            .animation(.linear(duration: 0.3), value: step.pct)
                    }
                }
                .frame(height: 6)

                if !step.message.isEmpty {
                    Text(step.message)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            if step.status == .failed, !step.message.isEmpty {
                Text(step.message)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(rowBackground)
        .cornerRadius(10)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch step.status {
        case .idle:
            Image(systemName: "circle")
                .foregroundColor(.secondary.opacity(0.4))
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }

    private var rowBackground: Color {
        switch step.status {
        case .idle:    return Color.clear
        case .running: return Color.cpPrimary.opacity(0.05)
        case .done:    return Color.green.opacity(0.05)
        case .failed:  return Color.red.opacity(0.05)
        }
    }
}

// MARK: - WizardNavBar  (Back / Next / Action buttons)

struct WizardNavBar: View {
    var backLabel: String    = "Back"
    var nextLabel: String    = "Continue"
    var nextDisabled: Bool   = false
    var showBack: Bool       = true
    var onBack: () -> Void   = {}
    var onNext: () -> Void   = {}
    var accentNext: Bool     = false

    var body: some View {
        HStack {
            if showBack {
                Button(backLabel, action: onBack)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onNext) {
                Text(nextLabel)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentNext ? .cpAccent : .cpPrimary)
            .disabled(nextDisabled)
        }
    }
}

// MARK: - ModePillPicker

struct ModePillPicker: View {
    @Binding var selection: PipelineMode

    var body: some View {
        HStack(spacing: 0) {
            pill("Auto",   mode: .auto,   icon: "arrow.down.circle")
            pill("Manual", mode: .manual, icon: "folder")
        }
        .background(Color.cpPrimary.opacity(0.08))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cpPrimary.opacity(0.2)))
    }

    private func pill(_ label: String, mode: PipelineMode, icon: String) -> some View {
        let selected = selection == mode
        return Button {
            withAnimation { selection = mode }
        } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(selected ? Color.cpPrimary : Color.clear)
                .foregroundColor(selected ? .white : .cpPrimary)
        }
        .buttonStyle(.plain)
        .cornerRadius(9)
    }
}

// MARK: - TimestampField

struct TimestampField: View {
    var label: String
    @Binding var value: String
    var placeholder: String = "00:00:00"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            TextField(placeholder, text: $value)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
        }
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

// MARK: - InfoBadge

struct InfoBadge: View {
    var text: String
    var color: Color = .cpPrimary
    var body: some View {
        Text(text)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}
