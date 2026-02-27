import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: PipelineViewModel
    @Environment(ServerManager.self) var server
    @EnvironmentObject var sse: SSEListener

    var body: some View {
        ZStack {
            Color.cpBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Step indicator strip (hidden on welcome/clean/done)
                if showStepStrip {
                    StepStrip(currentStep: vm.currentStep)
                        .padding(.horizontal, 32)
                        .padding(.top, 20)
                        .padding(.bottom, 4)
                }

                // Main content area with slide transitions
                ZStack {
                    switch vm.currentStep {
                    case .welcome:    WelcomeView()
                    case .source:     SourceView()
                    case .timestamps: TimestampsView()
                    case .metadata:   MetadataView()
                    case .processing: ProcessingView()
                    case .upload:     UploadView()
                    case .done:       DoneView()
                    case .clean:      CleanView()
                    }
                }
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    private var showStepStrip: Bool {
        switch vm.currentStep {
        case .welcome, .done, .clean: return false
        default: return true
        }
    }
}

// MARK: - Step indicator strip

struct StepStrip: View {
    var currentStep: WizardStep

    private let steps: [(WizardStep, String)] = [
        (.source,     "Source"),
        (.timestamps, "Timestamps"),
        (.metadata,   "Metadata"),
        (.processing, "Process"),
        (.upload,     "Upload"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.1.0.rawValue) { idx, pair in
                let (step, label) = pair
                let state = stepState(step)

                HStack(spacing: 6) {
                    // Circle
                    ZStack {
                        Circle()
                            .fill(state == .active  ? Color.cpPrimary :
                                  state == .past    ? Color.cpPrimary.opacity(0.2) :
                                  Color.secondary.opacity(0.15))
                            .frame(width: 22, height: 22)
                        if state == .past {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.cpPrimary)
                        } else {
                            Text("\(idx + 1)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(state == .active ? .white : .secondary)
                        }
                    }
                    Text(label)
                        .font(.system(size: 11, weight: state == .active ? .semibold : .regular))
                        .foregroundColor(state == .active ? .cpPrimary : .secondary)
                }

                if idx < steps.count - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                }
            }
        }
    }

    private enum State { case past, active, future }

    private func stepState(_ step: WizardStep) -> State {
        if step == currentStep { return .active }
        return step.rawValue < currentStep.rawValue ? .past : .future
    }
}

