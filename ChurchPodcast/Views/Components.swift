import SwiftUI

// MARK: - Brand colours

extension Color {
    static let cpPrimary    = Color(red: 0.22, green: 0.40, blue: 0.82)
    static let cpAccent     = Color(red: 0.95, green: 0.55, blue: 0.18)
    static let cpSurface    = Color(NSColor.controlBackgroundColor)
    static let cpBackground = Color(NSColor.windowBackgroundColor)
}

// MARK: - WizardCard

struct WizardCard<Content: View>: View {
    var title: String
    var subtitle: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3).fontWeight(.semibold)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            content
        }
        .padding(22)
        .background(Color.cpSurface)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
    }
}

// MARK: - StepProgressRow

struct StepProgressRow: View {
    var step: StepState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusIcon
                Text(step.label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if step.status == .running {
                    Text("\(step.pct)%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cpPrimary)
                } else if step.status == .done {
                    Text("Done").font(.caption).fontWeight(.semibold).foregroundColor(.green)
                }
            }

            if step.status == .running {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.cpPrimary.opacity(0.15))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.cpPrimary)
                            .frame(width: geo.size.width * CGFloat(step.pct) / 100.0,
                                   height: 5)
                            .animation(.linear(duration: 0.25), value: step.pct)
                    }
                }.frame(height: 5)

                if !step.message.isEmpty {
                    Text(step.message)
                        .font(.system(size: 10))
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
        .padding(10)
        .background(rowBG)
        .cornerRadius(9)
    }

    @ViewBuilder private var statusIcon: some View {
        switch step.status {
        case .idle:    Image(systemName: "circle").foregroundColor(.secondary.opacity(0.35))
        case .running: ProgressView().controlSize(.small)
        case .done:    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:  Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        }
    }

    private var rowBG: Color {
        switch step.status {
        case .idle:    return .clear
        case .running: return Color.cpPrimary.opacity(0.05)
        case .done:    return Color.green.opacity(0.05)
        case .failed:  return Color.red.opacity(0.05)
        }
    }
}

// MARK: - WizardNavBar

struct WizardNavBar: View {
    var backLabel:    String  = "Back"
    var nextLabel:    String  = "Continue"
    var nextDisabled: Bool    = false
    var showBack:     Bool    = true
    var accentNext:   Bool    = false
    var onBack:   () -> Void  = {}
    var onNext:   () -> Void  = {}

    var body: some View {
        HStack {
            if showBack {
                Button(backLabel, action: onBack)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
            }
            Spacer()
            Button(action: onNext) {
                Text(nextLabel)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20).padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentNext ? Color.cpAccent : Color.cpPrimary)
            .disabled(nextDisabled)
        }
    }
}

// MARK: - Small helpers

struct SectionHeader: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(.secondary)
            .textCase(.uppercase).tracking(0.6)
    }
}

struct InfoBadge: View {
    var text: String
    var color: Color = .cpPrimary
    var body: some View {
        Text(text)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(5)
    }
}

struct TimestampField: View {
    var label: String
    @Binding var value: String
    var placeholder: String = "00:00:00"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundColor(.secondary).textCase(.uppercase)
            TextField(placeholder, text: $value)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 108)
        }
    }
}

// MARK: - Pill toggle pair

struct PillToggle: View {
    var labelA: String
    var labelB: String
    @Binding var aSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            pill(labelA, selected: aSelected)  { aSelected = true  }
            pill(labelB, selected: !aSelected) { aSelected = false }
        }
        .background(Color.cpPrimary.opacity(0.07))
        .cornerRadius(9)
        .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.cpPrimary.opacity(0.18)))
    }

    private func pill(_ label: String, selected: Bool,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(selected ? Color.cpPrimary : Color.clear)
                .foregroundColor(selected ? .white : .cpPrimary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
