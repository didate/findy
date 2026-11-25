import SwiftUI

/// Shows a running copy or move, with a way to stop it.
struct OperationProgressView: View {
    let progress: OperationProgress
    let onCancel: () -> Void

    /// Most operations finish at once. The panel only shows for the ones that last.
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if progress.isMove {
                        Text("Moving…", bundle: .module)
                    } else {
                        Text("Copying…", bundle: .module)
                    }
                }
                .font(.callout.weight(.medium))
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button {
                onCancel()
            } label: {
                Text("Stop", bundle: .module)
            }
        }
        .padding(12)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .padding(12)
        .opacity(isVisible ? 1 : 0)
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            isVisible = true
        }
    }

    @ViewBuilder private var detail: some View {
        let completed = progress.completedBytes.formatted(.byteCount(style: .file))
        if let total = progress.totalBytes {
            Text("\(completed) of \(total.formatted(.byteCount(style: .file)))", bundle: .module)
        } else {
            Text(verbatim: completed)
        }
    }
}
