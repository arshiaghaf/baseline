import SwiftUI

struct UpdateActionButton: View {
    enum State {
        case ready
        case updating(progress: Double?)
        case done
        case failed
    }

    let state: State
    let onUpdate: () -> Void
    let readyLabel: String

    init(
        state: State,
        onUpdate: @escaping () -> Void,
        readyLabel: String = "Update"
    ) {
        self.state = state
        self.onUpdate = onUpdate
        self.readyLabel = readyLabel
    }

    var body: some View {
        switch state {
        case .ready:
            Button(readyLabel, action: onUpdate)
                .menuUpdateButtonStyle()
        case .updating(let progress):
            Button(action: {}) {
                if let progress {
                    UpdateProgressRingGlyphView(progress: progress)
                } else {
                    UpdateActionButtonGlyphView()
                }
            }
            .menuUpdateIconButtonStyle()
            .allowsHitTesting(false)
        case .done:
            Button(action: {}) {
                UpdateActionButtonDoneTransitionGlyphView()
            }
            .menuUpdateIconButtonStyle()
            .allowsHitTesting(false)
        case .failed:
            Button(action: {}) {
                UpdateActionButtonFailureGlyphView()
            }
            .menuDestructiveIconButtonStyle()
            .allowsHitTesting(false)
        }
    }
}

private struct UpdateActionButtonGlyphView: View {
    @State private var isSpinning = false

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .onAppear {
                isSpinning = true
            }
            .animation(
                .linear(duration: 0.9).repeatForever(autoreverses: false),
                value: isSpinning
            )
    }
}

private struct UpdateProgressRingGlyphView: View {
    let progress: Double
    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.32), lineWidth: 2)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    .white,
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        .onAppear {
            animatedProgress = clampedProgress(progress)
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeOut(duration: 0.22)) {
                animatedProgress = clampedProgress(newValue)
            }
        }
    }

    private func clampedProgress(_ raw: Double) -> Double {
        min(max(raw, 0), 1)
    }
}

private struct UpdateActionButtonFailureGlyphView: View {
    var body: some View {
        Image(systemName: "exclamationmark")
            .font(.caption.weight(.bold))
    }
}

private struct UpdateActionButtonDoneGlyphView: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.caption.weight(.bold))
    }
}

private struct UpdateActionButtonDoneTransitionGlyphView: View {
    @State private var showsCheckmark = false

    var body: some View {
        Group {
            if showsCheckmark {
                UpdateActionButtonDoneGlyphView()
            } else {
                UpdateProgressRingGlyphView(progress: 1.0)
            }
        }
        .onAppear {
            showsCheckmark = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 320_000_000)
                showsCheckmark = true
            }
        }
    }
}
