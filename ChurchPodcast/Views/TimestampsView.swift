import SwiftUI

struct TimestampsView: View {
    @EnvironmentObject var vm:  PipelineViewModel
    @EnvironmentObject var sse: SSEListener

    private var detectStep: StepState? { sse.steps.first(where: { $0.key == "detect" }) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                WizardCard(title: "Sermon Timestamps",
                           subtitle: "Set where the sermon starts and ends in the recording") {
                    VStack(alignment: .leading, spacing: 16) {
                        PillToggle(labelA: "Manual", labelB: "Auto-detect",
                                   aSelected: Binding(
                                       get:  { !vm.useAutoDetect },
                                       set:  { vm.useAutoDetect = !$0 }))

                        Divider()

                        if vm.useAutoDetect { autoSection }
                        else               { manualSection }
                    }
                }

                WizardNavBar(
                    nextDisabled: !timestampsValid,
                    onBack: { vm.goTo(.source) },
                    onNext: { vm.goTo(.metadata) }
                )
            }
            .padding(32)
        }
    }

    // MARK: - Auto-detect

    private var autoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let step = detectStep {
                switch step.status {
                case .idle:    autoPrompt
                case .running: StepProgressRow(step: step)
                case .done:    detectedResult
                case .failed:
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Auto-detect failed", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .medium)).foregroundColor(.orange)
                        Text(step.message).font(.caption).foregroundColor(.secondary)
                    }
                    .onAppear { vm.useAutoDetect = false }
                }
            } else {
                autoPrompt
            }
        }
    }

    private var autoPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scans the audio for long silence gaps — where intro music ends and the sermon begins, and where outro music starts.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await vm.runAutoDetect() }
            } label: {
                Label("Scan now", systemImage: "waveform.and.magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered).tint(.cpPrimary)
            .disabled(vm.detectRunning)
        }
    }

    private var detectedResult: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Timestamps detected", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.green)
            HStack(spacing: 20) {
                TimestampField(label: "Start", value: $vm.startTimestamp)
                TimestampField(label: "End",   value: $vm.endTimestamp)
            }
            Text("You can adjust these before continuing.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Manual

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enter the exact time where the sermon starts and ends in the recording.")
                .font(.caption).foregroundColor(.secondary)
            HStack(spacing: 24) {
                TimestampField(label: "Sermon starts at", value: $vm.startTimestamp)
                TimestampField(label: "Sermon ends at",   value: $vm.endTimestamp)
            }
            if let dur = estimatedDuration {
                Label("Sermon duration: \(dur)", systemImage: "clock")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var timestampsValid: Bool {
        !vm.startTimestamp.isEmpty && !vm.endTimestamp.isEmpty
    }

    private var estimatedDuration: String? {
        guard let s = ts(vm.startTimestamp), let e = ts(vm.endTimestamp), e > s else { return nil }
        let secs = Int(e - s); let m = secs / 60; let sec = secs % 60
        return String(format: "%d:%02d", m, sec)
    }

    private func ts(_ str: String) -> Double? {
        let p = str.split(separator: ":").compactMap { Double($0) }
        switch p.count {
        case 2: return p[0] * 60 + p[1]
        case 3: return p[0] * 3600 + p[1] * 60 + p[2]
        default: return nil
        }
    }
}
