import SwiftUI

struct DiffSummaryPanel: View {
    let diffResult: PDFDiffResult?
    let structuralDiff: PDFStructuralDiffResult?
    var onRegionTapped: ((CGRect) -> Void)?
    var aiResult: AIAnalysisResult?
    var isAnalyzing: Bool = false
    var aiError: String?
    var onRetry: (() -> Void)?

    @State private var isPixelExpanded = true
    @State private var isMetadataExpanded = true
    @State private var isTextExpanded = true
    @State private var isFontsExpanded = true
    @State private var isPageSizeExpanded = true
    @State private var isVisualExpanded = true
    @State private var isTextCompExpanded = true
    @State private var isQCExpanded = true
    @State private var isAnomaliesExpanded = true

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
                            .foregroundStyle(DesignTokens.Status.pass)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                    }
                }

                // AI Analysis sections
                if isAnalyzing {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Analyzing with AI...")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                if let error = aiError {
                    HStack {
                        Image(systemName: "exclamation.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let retry = onRetry {
                            Button("Retry") { retry() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let ai = aiResult {
                    Divider().padding(.vertical, 4)

                    aiVisualChangesSection(ai.visualChanges)
                    aiTextComparisonSection(ai.textComparison)
                    aiQCSection(ai.qcChecklist)
                    aiAnomaliesSection(ai.anomalies)

                    Button {
                        copyAIReport(ai)
                    } label: {
                        Label("Copy AI Report", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
                }

                if diffResult == nil && structuralDiff == nil {
                    Text("No comparison data")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DesignTokens.Spacing.md)
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
                        .foregroundStyle(DesignTokens.similarityColor(result.similarityScore))
                }

                // Progress bar
                ProgressView(value: result.similarityScore)
                    .tint(DesignTokens.similarityColor(result.similarityScore))

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
                .font(DesignTokens.Typo.sectionHeader)
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
                .font(DesignTokens.Typo.sectionHeader)
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
                .font(DesignTokens.Typo.sectionHeader)
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
                .font(DesignTokens.Typo.sectionHeader)
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
                .font(DesignTokens.Typo.sectionHeader)
        }
    }

    // MARK: - AI Analysis Sections

    @ViewBuilder
    private func aiVisualChangesSection(_ text: String) -> some View {
        DisclosureGroup(isExpanded: $isVisualExpanded) {
            Text(text)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Label("Visual Changes", systemImage: "eye")
                .font(DesignTokens.Typo.sectionHeader)
        }
    }

    @ViewBuilder
    private func aiTextComparisonSection(_ text: String) -> some View {
        DisclosureGroup(isExpanded: $isTextCompExpanded) {
            Text(text)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Label("Text Comparison", systemImage: "text.magnifyingglass")
                .font(DesignTokens.Typo.sectionHeader)
        }
    }

    @ViewBuilder
    private func aiQCSection(_ items: [QCCheckItem]) -> some View {
        DisclosureGroup(isExpanded: $isQCExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: DesignTokens.qcStatusIcon(item.status))
                            .foregroundStyle(DesignTokens.qcStatusColor(item.status))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.check)
                                .font(.caption.bold())
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Label("Prepress QC", systemImage: "checklist")
                .font(DesignTokens.Typo.sectionHeader)
        }
    }

    @ViewBuilder
    private func aiAnomaliesSection(_ text: String) -> some View {
        DisclosureGroup(isExpanded: $isAnomaliesExpanded) {
            VStack(alignment: .leading) {
                if text != "No issues found" {
                    Text(text)
                        .font(.caption)
                        .textSelection(.enabled)
                        .padding(8)
                        .background(DesignTokens.Status.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                } else {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Label("Anomalies", systemImage: "exclamationmark.triangle")
                .font(DesignTokens.Typo.sectionHeader)
        }
    }

    private func copyAIReport(_ result: AIAnalysisResult) {
        var report = "## AI Analysis Report\n\n"
        report += "### Visual Changes\n\(result.visualChanges)\n\n"
        report += "### Text Comparison\n\(result.textComparison)\n\n"
        report += "### Prepress QC\n"
        for item in result.qcChecklist {
            let icon = item.status == .pass ? "✓" : item.status == .warn ? "⚠" : "✗"
            report += "\(icon) \(item.check): \(item.detail)\n"
        }
        report += "\n### Anomalies\n\(result.anomalies)\n"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}
