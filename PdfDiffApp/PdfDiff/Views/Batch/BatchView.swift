import SwiftUI
import UniformTypeIdentifiers

struct BatchView: View {
    @State var viewModel: BatchViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.pairs.isEmpty {
                dropZone
            } else {
                batchToolbar
                Divider()
                batchTable
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop a folder of PDFs here")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Files will be auto-matched by name (v1/v2, old/new)")
                .font(DesignTokens.Typo.toolbarLabel)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        Task { @MainActor in
                            viewModel.addFolder(url: url)
                        }
                    }
                }
            }
            return true
        }
    }

    private var batchToolbar: some View {
        HStack {
            Text("\(viewModel.pairs.count) pairs found")
                .font(DesignTokens.Typo.sectionHeader)

            Spacer()

            if viewModel.isProcessing {
                ProgressView()
                    .controlSize(.small)
                Text("\(viewModel.completedCount)/\(viewModel.totalCount)")
                    .font(DesignTokens.Typo.toolbarLabel)
            }

            Button("Process All") {
                Task { await viewModel.processAll() }
            }
            .disabled(viewModel.isProcessing || viewModel.pairs.isEmpty)

            Button("Clear") {
                viewModel.pairs = []
            }
            .disabled(viewModel.isProcessing)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private var batchTable: some View {
        Table(viewModel.pairs) {
            TableColumn("Left") { pair in Text(pair.leftName).font(DesignTokens.Typo.toolbarLabel) }
            TableColumn("Right") { pair in Text(pair.rightName).font(DesignTokens.Typo.toolbarLabel) }
            TableColumn("Similarity") { pair in
                if let score = pair.similarityScore {
                    Text(String(format: "%.1f%%", score * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(score > 0.99 ? DesignTokens.Status.pass : score > 0.9 ? DesignTokens.Status.warn : DesignTokens.Status.fail)
                } else {
                    Text("-").foregroundStyle(.secondary)
                }
            }
            .width(80)
            TableColumn("Status") { pair in
                switch pair.status {
                case .pending: Text("Pending").font(.caption).foregroundStyle(.secondary)
                case .processing: ProgressView().controlSize(.mini)
                case .complete: Image(systemName: "checkmark.circle.fill").foregroundStyle(DesignTokens.Status.pass)
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DesignTokens.Status.fail)
                }
            }
            .width(60)
        }
    }
}
