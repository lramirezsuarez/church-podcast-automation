import SwiftUI

struct TimestampsView: View {
    @EnvironmentObject var vm: PipelineViewModel
    @EnvironmentObject var sse: SSEListener

    private var detectStep: StepState? {
        sse.steps.first(where: { $0.key == "detect" })
    }

    var body: some View {
        VStack(spacing: 24) {
            WizardCard(
                title: "Sermon Timestamps",
                subtitle: "Set where the sermon starts and ends in the broadcast"
            ) {
                VStack(alignment: .leading, spacing: 20) {

                    // Method toggle
                    HStack(spacing: 0) {
                        methodPill("Manual", selected: !vm.useAutoDetect) {
                            vm.useAutoDetect = false
                        }
                        methodPill("Auto-detect", selected: vm.useAutoDetect) {
                            vm.useAutoDetect = true
                        }
                    }
                    .background(Color.cpPrimary.opacity(0.06))
                    .cornerRadius(9)

                    Divider()

                    if vm.useAutoDetect {
                        autoDetectSection
                    } else {
                        manualSection
                    }
                }
            }

            WizardNavBar(
                nextLabel:    "Continue",
                nextDisabled: !timestampsValid,
                onBack: { vm.goTo(.source) },
                onNext: { vm.goTo(.metadata) }
            )
        }
        .padding(32)
        .onAppear {
            // If auto-detect was chosen and a file is available, kick it off
            if vm.useAutoDetect && !vm.downloadedFilePath.isEmpty && vm.startTimestamp.isEmpty {
                Task { await vm.runAutoDetect() }
            }
        }
    }

    // MARK: - Auto-detect section

    private var autoDetectSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let step = detectStep {
                switch step.status {
                case .idle:
                    autoDetectPrompt
                case .running:
                    VStack(alignment: .leading, spacing: 10) {
                        StepProgressRow(step: step)
                        Text("Scanning audio for silence gaps at the intro and outro…")
                            .font(.caption).foregroundColor(.secondary)
                    }
                case .done:
                    detectedTimestampsResult
                case .failed:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text("Auto-detect failed").font(.system(size: 13, weight: .medium))
                        }
                        Text(step.message).font(.caption).foregroundColor(.secondary)
                        Text("Switching to manual entry.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .onAppear { vm.useAutoDetect = false }
                }
            } else {
                autoDetectPrompt
            }
        }
    }

    private var autoDetectPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Auto-detect scans the audio for long silence gaps — the point where intro music ends and the sermon begins, and where outro music starts.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await vm.runAutoDetect() }
            } label: {
                Label("Scan now", systemImage: "waveform.and.magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(.cpPrimary)
            .disabled(vm.detectRunning)
        }
    }

    private var detectedTimestampsResult: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("Timestamps detected").font(.system(size: 13, weight: .semibold))
            }
            HStack(spacing: 20) {
                TimestampField(label: "Start", value: $vm.startTimestamp)
                TimestampField(label: "End",   value: $vm.endTimestamp)
            }
            Text("You can edit these values before continuing.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Manual section

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter the start and end times of the sermon in the broadcast recording.")
                .font(.caption).foregroundColor(.secondary)

            HStack(spacing: 24) {
                TimestampField(label: "Sermon starts at", value: $vm.startTimestamp)
                TimestampField(label: "Sermon ends at",   value: $vm.endTimestamp)
            }

            if let dur = estimatedDuration {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.caption).foregroundColor(.secondary)
                    Text("Sermon duration: \(dur)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private var timestampsValid: Bool {
        !vm.startTimestamp.isEmpty && !vm.endTimestamp.isEmpty
    }

    private var estimatedDuration: String? {
        guard let s = parseTs(vm.startTimestamp), let e = parseTs(vm.endTimestamp), e > s else { return nil }
        let secs = Int(e - s)
        let m = secs / 60; let sec = secs % 60
        return String(format: "%d:%02d", m, sec)
    }

    private func parseTs(_ ts: String) -> Double? {
        let parts = ts.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }

    private func methodPill(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
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
