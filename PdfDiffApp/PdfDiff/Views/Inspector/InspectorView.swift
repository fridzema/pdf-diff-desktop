import SwiftUI

struct InspectorView: View {
    @State var viewModel: InspectorViewModel
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager?

    var body: some View {
        VSplitView {
            // Top area: page renderer + optional sidebar
            VStack(spacing: 0) {
                toolbar
                Divider()

                HStack(spacing: 0) {
                    // Canvas with pins
                    pageCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Inspection sidebar (slides in from right)
                    if viewModel.showInspectionSidebar, let result = viewModel.inspectionResult {
                        Divider()
                        InspectionSidebar(
                            result: result,
                            selectedIssueId: $viewModel.selectedIssueId,
                            showPins: $viewModel.showPins,
                            onClose: { viewModel.showInspectionSidebar = false }
                        )
                        .transition(.move(edge: .trailing))
                    }
                }
            }
            .frame(minHeight: 300)
            .animation(.easeInOut(duration: 0.25), value: viewModel.showInspectionSidebar)

            // Preflight + Metadata panel
            VStack(spacing: 0) {
                if let preflight = viewModel.preflightResult {
                    PreflightPanel(
                        result: preflight,
                        onNavigateToPage: { page in
                            viewModel.currentPage = page
                            Task { await viewModel.loadDocument(viewModel.document!) }
                        }
                    )
                    Divider()
                } else if viewModel.isPreflighting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Running preflight...").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(8)
                    Divider()
                }

                MetadataPanel(metadata: viewModel.metadata, pageMetadata: viewModel.pagesMetadata)
            }
            .frame(minHeight: 150, maxHeight: 300)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Button(action: { viewModel.previousPage() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(viewModel.currentPage == 0)

            Text("Page \(viewModel.currentPage + 1) of \(viewModel.document?.pageCount ?? 0)")
                .font(.body.monospacedDigit())

            Button(action: { viewModel.nextPage() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(viewModel.currentPage >= (viewModel.document?.pageCount ?? 1) - 1)

            Picker("", selection: $viewModel.showSeparations) {
                Text("Page").tag(false)
                Text("Separations").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .onChange(of: viewModel.showSeparations) { _, show in
                if show && viewModel.separationChannels.isEmpty {
                    Task { await viewModel.loadSeparations() }
                }
            }

            Spacer()

            if viewModel.isInspecting {
                ProgressView()
                    .controlSize(.small)
                Text("Inspecting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = viewModel.inspectionError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Retry") {
                    if let key = settingsManager?.apiKey, !key.isEmpty {
                        Task { await viewModel.runInspection(apiKey: key) }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if viewModel.inspectionResult != nil && !viewModel.showInspectionSidebar {
                Button {
                    viewModel.showInspectionSidebar = true
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Show inspection results")
            }

            Button {
                if let key = settingsManager?.apiKey, !key.isEmpty {
                    Task { await viewModel.runInspection(apiKey: key) }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                    Text("Inspect")
                }
            }
            .disabled(!viewModel.canRunInspection || settingsManager?.hasAPIKey != true)
            .help(settingsManager?.hasAPIKey != true ? "Set API key in Settings (\u{2318},)" : "Run AI inspection")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Page Canvas

    @ViewBuilder
    private var pageCanvas: some View {
        if viewModel.showSeparations {
            SeparationViewer(channels: $viewModel.separationChannels)
        } else if viewModel.isRendering {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let image = viewModel.renderedImage {
            ZoomableContainer {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        // Pin overlay — uses .overlay so GeometryReader matches the image bounds
                        if viewModel.showPins && viewModel.currentPage == 0,
                           let result = viewModel.inspectionResult {
                            GeometryReader { geo in
                                ForEach(result.issues.filter { $0.location != nil }) { issue in
                                    let loc = issue.location!
                                    IssuePinView(
                                        issue: issue,
                                        isSelected: viewModel.selectedIssueId == issue.id
                                    ) {
                                        viewModel.selectedIssueId = viewModel.selectedIssueId == issue.id ? nil : issue.id
                                    }
                                    .position(
                                        x: loc.centerX * geo.size.width,
                                        y: loc.centerY * geo.size.height
                                    )
                                }
                            }
                        }
                    }
                    .overlay {
                        // Barcode overlay
                        if viewModel.showBarcodeOverlay && !viewModel.detectedBarcodes.isEmpty {
                            GeometryReader { geo in
                                ForEach(viewModel.detectedBarcodes) { barcode in
                                    Rectangle()
                                        .stroke(Color.blue, lineWidth: 2)
                                        .background(Color.blue.opacity(0.1))
                                        .frame(
                                            width: barcode.boundingBox.width * geo.size.width,
                                            height: barcode.boundingBox.height * geo.size.height
                                        )
                                        .position(
                                            x: (barcode.boundingBox.midX) * geo.size.width,
                                            y: (barcode.boundingBox.midY) * geo.size.height
                                        )
                                }
                            }
                        }
                    }
            }
        } else {
            Text("No page rendered")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
