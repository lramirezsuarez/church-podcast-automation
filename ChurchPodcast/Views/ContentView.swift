import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm:     PipelineViewModel
    @EnvironmentObject var server: ServerManager
    @EnvironmentObject var sse:    SSEListener

    var body: some View {
        ZStack {
            Color.cpBackground.ignoresSafeArea()

            VStack(spacing: 0) {

                // Step strip — hidden on non-wizard screens
                if showStepStrip {
                    StepStrip(currentStep: vm.currentStep)
                        .padding(.horizontal, 32)
                        .padding(.top, 18)
                        .padding(.bottom, 2)
                }

                // Wizard content — slides in/out
                Group {
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
                .frame(maxWidth: 580)
                .frame(maxWidth: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)))
                .id(vm.currentStep)
            }
        }
        .frame(minWidth: 620, minHeight: 540)
        .onAppear { Task { await vm.loadConfig() } }
    }

    private var showStepStrip: Bool {
        switch vm.currentStep {
        case .welcome, .done, .clean: return false
        default: return true
        }
    }
}

// MARK: - Step strip

struct StepStrip: View {
    var currentStep: WizardStep

    private let steps: [(WizardStep, String)] = [
        (.source,     "Source"),
        (.timestamps, "Timestamps"),
        (.metadata,   "Details"),
        (.processing, "Process"),
        (.upload,     "Upload"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.1.0.rawValue) { idx, pair in
                let (step, label) = pair
                let st = state(step)

                HStack(spacing: 5) {
                    Circle()
                        .fill(st == .active  ? Color.cpPrimary :
                              st == .past    ? Color.cpPrimary.opacity(0.25) :
                              Color.secondary.opacity(0.18))
                        .frame(width: 20, height: 20)
                        .overlay {
                            if st == .past {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.cpPrimary)
                            } else {
                                Text("\(idx + 1)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(st == .active ? .white : .secondary)
                            }
                        }

                    Text(label)
                        .font(.system(size: 11, weight: st == .active ? .semibold : .regular))
                        .foregroundColor(st == .active ? .cpPrimary : .secondary)
                }

                if idx < steps.count - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1).frame(maxWidth: .infinity)
                        .padding(.horizontal, 5)
                }
            }
        }
    }

    private enum State { case past, active, future }
    private func state(_ step: WizardStep) -> State {
        if step == currentStep { return .active }
        return step.rawValue < currentStep.rawValue ? .past : .future
    }
}
