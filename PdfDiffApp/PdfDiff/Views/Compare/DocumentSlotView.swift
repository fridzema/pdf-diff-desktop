import SwiftUI

struct DocumentSlotView: View {
    let label: String
    let document: OpenedDocument?
    let onDrop: (String) -> Void
    let onClear: () -> Void

    @State private var isTargeted = false

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
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                        )
                )
            }
        }
        .onDrop(of: [.plainText], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: String.self) { path, _ in
                    if let path {
                        DispatchQueue.main.async {
                            onDrop(path)
                        }
                    }
                }
            }
            return true
        }
    }
}
