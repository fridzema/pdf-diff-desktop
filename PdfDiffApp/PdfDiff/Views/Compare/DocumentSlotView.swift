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
        VStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let doc = document {
                // Filled slot
                HStack(spacing: 8) {
                    Image(systemName: "doc.richtext")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.fileName)
                            .font(.body)
                            .lineLimit(1)
                        Text("\(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s")")
                            .font(.caption)
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
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.08))
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
            } else {
                // Empty slot
                VStack(spacing: 4) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Drop PDF here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            dropFailed ? Color.red : (isTargeted ? Color.accentColor : Color.secondary.opacity(0.3)),
                            style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                        )
                )
                .overlay {
                    if dropSucceeded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: dropSucceeded)
                .scaleEffect(isTargeted ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
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
