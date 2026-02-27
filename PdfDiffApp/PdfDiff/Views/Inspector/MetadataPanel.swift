import SwiftUI

struct MetadataPanel: View {
    let metadata: PDFMetadata?
    let pageMetadata: [PDFPageMetadata]

    enum Tab: String, CaseIterable { case metadata, fonts, images, colors }
    @State private var selectedTab: Tab = .metadata

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue.capitalized).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(DesignTokens.Spacing.sm)

            Divider()

            ScrollView {
                switch selectedTab {
                case .metadata:
                    metadataContent
                case .fonts:
                    fontsContent
                case .images:
                    imagesContent
                case .colors:
                    colorsContent
                }
            }
            .padding(DesignTokens.Spacing.sm)
        }
    }

    @ViewBuilder
    private var metadataContent: some View {
        if let m = metadata {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Title", m.title ?? "—")
                row("Author", m.author ?? "—")
                row("Creator", m.creator ?? "—")
                row("Producer", m.producer ?? "—")
                row("PDF Version", m.pdfVersion)
                row("Pages", "\(m.pageCount)")
                row("File Size", ByteCountFormatter.string(fromByteCount: Int64(m.fileSizeBytes), countStyle: .file))
                row("Encrypted", m.isEncrypted ? "Yes" : "No")
            }
        } else {
            Text("No document loaded").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var fontsContent: some View {
        let allFonts = Set(pageMetadata.flatMap(\.fontNames)).sorted()
        if allFonts.isEmpty {
            Text("No fonts found").foregroundStyle(.secondary)
        } else {
            ForEach(allFonts, id: \.self) { font in
                Text(font).font(.system(.body, design: .monospaced))
            }
        }
    }

    @ViewBuilder
    private var imagesContent: some View {
        let totalImages = pageMetadata.reduce(0) { $0 + $1.imageCount }
        Text("Total images: \(totalImages)")
    }

    @ViewBuilder
    private var colorsContent: some View {
        if let m = metadata {
            ForEach(m.colorProfiles, id: \.self) { profile in
                Text(profile)
            }
            if m.colorProfiles.isEmpty {
                Text("No ICC profiles found").foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
