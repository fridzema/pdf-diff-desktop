import SwiftUI

struct InspectorView: View {
    @State var viewModel: InspectorViewModel
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            // Full-height canvas with overlay drawers
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    pageCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Inspection sidebar (right-side glass overlay)
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

                // Bottom overlay drawer
                GeometricGlassDrawer(isPresented: viewModel.activeDrawer != nil) {
                    drawerContent
                }
                .animation(DesignTokens.Motion.snappy, value: viewModel.activeDrawer)
            }
        }
        .frame(minHeight: 300)
        .animation(DesignTokens.Motion.snappy, value: viewModel.showInspectionSidebar)
        .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in viewModel.zoomIn() }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in viewModel.zoomOut() }
        .onReceive(NotificationCenter.default.publisher(for: .zoomFit)) { _ in viewModel.zoomFit() }
        .onKeyPress(.escape) {
            if viewModel.activeDrawer != nil {
                viewModel.dismissDrawer()
                return .handled
            }
            return .ignored
        }
    }

    @ViewBuilder
    private var drawerContent: some View {
        switch viewModel.activeDrawer {
        case .metadata:
            MetadataPanel(metadata: viewModel.metadata, pageMetadata: viewModel.pagesMetadata)
        case .preflight:
            if let result = viewModel.preflightResult {
                PreflightPanel(result: result, onNavigateToPage: { page in
                    viewModel.currentPage = page
                })
            } else {
                Text("No preflight results")
                    .foregroundStyle(.secondary)
                    .padding(DesignTokens.Spacing.lg)
            }
        case .inspection:
            if let result = viewModel.inspectionResult {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("AI Inspection")
                        .font(DesignTokens.Typo.sectionHeader)
                    Text(result.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No inspection results")
                    .foregroundStyle(.secondary)
                    .padding(DesignTokens.Spacing.lg)
            }
        case nil:
            EmptyView()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // Page navigation
            Button(action: { viewModel.previousPage() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(viewModel.currentPage == 0)

            Text("Page \(viewModel.currentPage + 1) of \(viewModel.document?.pageCount ?? 0)")
                .font(DesignTokens.Typo.bodyMono)

            Button(action: { viewModel.nextPage() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(viewModel.currentPage >= (viewModel.document?.pageCount ?? 1) - 1)

            Divider().frame(height: 20)

            ZoomToolbar(
                zoomLevel: $viewModel.zoomLevel,
                onZoomIn: { viewModel.zoomIn() },
                onZoomOut: { viewModel.zoomOut() },
                onZoomFit: { viewModel.zoomFit() }
            )

            Spacer()

            // Inspection status/controls
            if viewModel.isInspecting {
                ProgressView()
                    .controlSize(.small)
                Text("Inspecting...")
                    .font(DesignTokens.Typo.toolbarLabel)
                    .foregroundStyle(.secondary)
            } else if let error = viewModel.inspectionError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Status.warn)
                Text(error)
                    .font(DesignTokens.Typo.toolbarLabel)
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

            Button {
                if let key = settingsManager?.apiKey, !key.isEmpty {
                    Task { await viewModel.runInspection(apiKey: key) }
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "wand.and.stars")
                    Text("Inspect")
                }
            }
            .disabled(!viewModel.canRunInspection || settingsManager?.hasAPIKey != true)
            .help(settingsManager?.hasAPIKey != true ? "Set API key in Settings (\u{2318},)" : "Run AI inspection")

            Divider().frame(height: 20)

            // Drawer toggle buttons
            drawerToggle(.metadata, icon: "info.circle", label: "Metadata")
            drawerToggle(.preflight, icon: "checkmark.shield", label: "Preflight")

            if viewModel.inspectionResult != nil {
                drawerToggle(.inspection, icon: "wand.and.stars", label: "AI Results")
            }

            if viewModel.inspectionResult != nil && !viewModel.showInspectionSidebar {
                Button {
                    viewModel.showInspectionSidebar = true
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Show inspection sidebar")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private func drawerToggle(_ panel: InspectorViewModel.DrawerPanel, icon: String, label: String) -> some View {
        Button {
            viewModel.toggleDrawer(panel)
        } label: {
            Image(systemName: icon)
        }
        .help(label)
        .foregroundStyle(viewModel.activeDrawer == panel ? Color.accentColor : .secondary)
    }

    // MARK: - Page Canvas

    @ViewBuilder
    private var pageCanvas: some View {
        if viewModel.isRendering {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let image = viewModel.renderedImage {
            ZoomableContainer(zoom: $viewModel.zoomLevel, offset: $viewModel.panOffset) {
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
            }
        } else {
            Text("No page rendered")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
