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
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop a folder of PDFs here")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Files will be auto-matched by name (v1/v2, old/new)")
                .font(.caption)
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
                .font(.headline)

            Spacer()

            if viewModel.isProcessing {
                ProgressView()
                    .controlSize(.small)
                Text("\(viewModel.completedCount)/\(viewModel.totalCount)")
                    .font(.caption)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var batchTable: some View {
        Table(viewModel.pairs) {
            TableColumn("Left") { pair in Text(pair.leftName).font(.caption) }
            TableColumn("Right") { pair in Text(pair.rightName).font(.caption) }
            TableColumn("Similarity") { pair in
                if let score = pair.similarityScore {
                    Text(String(format: "%.1f%%", score * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(score > 0.99 ? .green : score > 0.9 ? .orange : .red)
                } else {
                    Text("-").foregroundStyle(.secondary)
                }
            }
            .width(80)
            TableColumn("Status") { pair in
                switch pair.status {
                case .pending: Text("Pending").font(.caption).foregroundStyle(.secondary)
                case .processing: ProgressView().controlSize(.mini)
                case .complete: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            .width(60)
        }
    }
}
