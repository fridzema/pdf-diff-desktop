import SwiftUI

struct DiffSummaryPanel: View {
    let diffResult: PDFDiffResult?
    let structuralDiff: PDFStructuralDiffResult?
    var onRegionTapped: ((CGRect) -> Void)?

    @State private var isPixelExpanded = true
    @State private var isMetadataExpanded = true
    @State private var isTextExpanded = true
    @State private var isFontsExpanded = true
    @State private var isPageSizeExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Pixel diff summary
                if let result = diffResult {
                    pixelDiffSection(result)
                }

                // Structural diff sections
                if let structural = structuralDiff {
                    if !structural.metadataChanges.isEmpty {
                        metadataSection(structural.metadataChanges)
                    }

                    if !structural.textChanges.isEmpty {
                        textChangesSection(structural.textChanges)
                    }

                    if !structural.fontChanges.isEmpty {
                        fontChangesSection(structural.fontChanges)
                    }

                    if !structural.pageSizeChanges.isEmpty {
                        pageSizeSection(structural.pageSizeChanges)
                    }

                    if structural.metadataChanges.isEmpty &&
                       structural.textChanges.isEmpty &&
                       structural.fontChanges.isEmpty &&
                       structural.pageSizeChanges.isEmpty {
                        Label("No structural differences found", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .padding(.vertical, 4)
                    }
                }

                if diffResult == nil && structuralDiff == nil {
                    Text("No comparison data")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Pixel Diff Section

    @ViewBuilder
    private func pixelDiffSection(_ result: PDFDiffResult) -> some View {
        DisclosureGroup(isExpanded: $isPixelExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                // Similarity gauge
                HStack {
                    Text("Similarity")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f%%", result.similarityScore * 100))
                        .font(.body.monospacedDigit().bold())
                        .foregroundStyle(similarityColor(result.similarityScore))
                }

                // Progress bar
                ProgressView(value: result.similarityScore)
                    .tint(similarityColor(result.similarityScore))

                // Pixel counts
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Changed pixels").foregroundStyle(.secondary)
                        Text("\(result.changedPixelCount)").monospacedDigit()
                    }
                    GridRow {
                        Text("Total pixels").foregroundStyle(.secondary)
                        Text("\(result.totalPixelCount)").monospacedDigit()
                    }
                }

                // Changed regions
                if !result.changedRegions.isEmpty {
                    Text("Changed regions: \(result.changedRegions.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(result.changedRegions.enumerated()), id: \.offset) { index, region in
                        Button {
                            onRegionTapped?(region)
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.dashed")
                                    .foregroundStyle(.orange)
                                Text("Region \(index + 1)")
                                Spacer()
                                Text(String(format: "%.0fx%.0f at (%.0f,%.0f)",
                                            region.width, region.height,
                                            region.origin.x, region.origin.y))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Pixel Comparison", systemImage: "square.split.2x1")
                .font(.headline)
        }
    }

    // MARK: - Metadata Section

    @ViewBuilder
    private func metadataSection(_ changes: [(field: String, left: String?, right: String?)]) -> some View {
        DisclosureGroup(isExpanded: $isMetadataExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.field)
                            .font(.caption.bold())
                        HStack(spacing: 4) {
                            Text(change.left ?? "—")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(change.right ?? "—")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Metadata Changes (\(changes.count))", systemImage: "info.circle")
                .font(.headline)
        }
    }

    // MARK: - Text Changes Section

    @ViewBuilder
    private func textChangesSection(_ changes: [(page: UInt32, left: String, right: String)]) -> some View {
        DisclosureGroup(isExpanded: $isTextExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Page \(change.page + 1)")
                            .font(.caption.bold())

                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading) {
                                Text("Left")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(change.left.prefix(200))
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(5)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading) {
                                Text("Right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(change.right.prefix(200))
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .lineLimit(5)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Divider()
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Text Changes (\(changes.count))", systemImage: "text.redline")
                .font(.headline)
        }
    }

    // MARK: - Font Changes Section

    @ViewBuilder
    private func fontChangesSection(_ changes: [(page: UInt32, left: [String], right: [String])]) -> some View {
        DisclosureGroup(isExpanded: $isFontsExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Page \(change.page + 1)")
                            .font(.caption.bold())
                        Text("Left: \(change.left.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text("Right: \(change.right.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Font Changes (\(changes.count))", systemImage: "textformat")
                .font(.headline)
        }
    }

    // MARK: - Page Size Section

    @ViewBuilder
    private func pageSizeSection(_ changes: [(page: UInt32, leftSize: CGSize, rightSize: CGSize)]) -> some View {
        DisclosureGroup(isExpanded: $isPageSizeExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                    HStack {
                        Text("Page \(change.page + 1)")
                            .font(.caption.bold())
                        Spacer()
                        Text(String(format: "%.1f x %.1f", change.leftSize.width, change.leftSize.height))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.red)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f x %.1f", change.rightSize.width, change.rightSize.height))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Page Size Changes (\(changes.count))", systemImage: "rectangle.expand.vertical")
                .font(.headline)
        }
    }

    // MARK: - Helpers

    private func similarityColor(_ score: Double) -> Color {
        if score >= 0.99 { return .green }
        if score >= 0.90 { return .yellow }
        return .red
    }
}
