import SwiftUI
import UniformTypeIdentifiers

struct DocumentSlotView: View {
    let label: String
    let document: OpenedDocument?
    let onDrop: (String) -> Void
    let onClear: () -> Void

    @State private var isTargeted = false
    @State private var dropFailed = false
    @State private var dropSucceeded = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Text(label)
                .font(DesignTokens.Typo.toolbarLabel)
                .foregroundStyle(.secondary)

            if let doc = document {
                // Filled slot
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "doc.richtext")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Text(doc.fileName)
                            .font(.body)
                            .lineLimit(1)
                        Text("\(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s")")
                            .font(DesignTokens.Typo.toolbarLabel)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(DesignTokens.Spacing.md)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            } else {
                // Empty slot
                VStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "arrow.down.doc")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Drop PDF here")
                        .font(DesignTokens.Typo.toolbarLabel)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay {
                    if dropSucceeded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(DesignTokens.Status.pass)
                            .transition(.scale.combined(with: .opacity))
                    }
                    if dropFailed {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(DesignTokens.Status.fail)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(DesignTokens.Motion.bouncy, value: isTargeted)
                .animation(DesignTokens.Motion.snappy, value: dropSucceeded)
                .animation(DesignTokens.Motion.snappy, value: dropFailed)
                .scaleEffect(isTargeted ? 1.02 : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        // Try file URL first (Finder drops)
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "pdf" else {
                        DispatchQueue.main.async { flashDropFailed() }
                        return
                    }
                    DispatchQueue.main.async {
                        onDrop(url.path)
                        flashDropSucceeded()
                    }
                }
                return
            }
        }
        // Fall back to plain text (sidebar drags)
        for provider in providers {
            _ = provider.loadObject(ofClass: String.self) { path, _ in
                if let path {
                    DispatchQueue.main.async {
                        onDrop(path)
                        flashDropSucceeded()
                    }
                }
            }
        }
    }

    private func flashDropFailed() {
        dropFailed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            dropFailed = false
        }
    }

    private func flashDropSucceeded() {
        dropSucceeded = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dropSucceeded = false
        }
    }
}
