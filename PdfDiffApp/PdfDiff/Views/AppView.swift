import SwiftUI
import UniformTypeIdentifiers

struct AppView: View {
    @State var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            DetailAreaView(viewModel: viewModel)
        }
        .frame(minWidth: 900, minHeight: 650)
        .onDrop(of: [.pdf], isTargeted: $viewModel.isDropTargeted) { providers in
            viewModel.handleDrop(providers: providers)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

// MARK: - Detail Area

struct DetailAreaView: View {
    let viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            if !viewModel.documents.isEmpty {
                tabBar
                Divider()
            }

            // Content
            switch viewModel.activeTab {
            case .inspector:
                if let selected = viewModel.selectedDocument {
                    DocumentDetailView(document: selected, pdfService: viewModel.pdfService)
                } else if viewModel.documents.isEmpty {
                    DropZoneView(viewModel: viewModel)
                } else {
                    Text("Select a document in the sidebar")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .compare:
                CompareView(
                    viewModel: viewModel.compareViewModel,
                    findDocument: { viewModel.document(forPath: $0) },
                    openFileAtPath: { path in
                        let url = URL(fileURLWithPath: path)
                        viewModel.openFiles(urls: [url])
                        return viewModel.document(forPath: path)
                    }
                )
            case .batch:
                BatchView(viewModel: viewModel.batchViewModel)
            }
        }
    }

    private var tabBar: some View {
        GlassEffectContainer {
            HStack {
                Spacer()
                Picker("", selection: Binding(
                    get: { viewModel.activeTab },
                    set: { viewModel.activeTab = $0 }
                )) {
                    ForEach(AppViewModel.ActiveTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                Spacer()
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            List(viewModel.documents, selection: Binding(
                get: { viewModel.selectedDocumentIDs },
                set: { viewModel.selectedDocumentIDs = $0 }
            )) { doc in
                DocumentRow(document: doc)
                    .draggable(doc.path) // Enable drag from sidebar
            }
            .navigationTitle("Documents")

            // Compare button at bottom
            if viewModel.selectedDocumentIDs.count == 2 {
                Divider()
                Button {
                    viewModel.enterCompareModeFromSelection()
                } label: {
                    Label("Compare Selected", systemImage: "square.split.2x1")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(DesignTokens.Spacing.md)
            }
        }
    }
}

struct DocumentRow: View {
    let document: OpenedDocument

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "doc.richtext")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(document.fileName)
                    .lineLimit(1)
                Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s")")
                    .font(DesignTokens.Typo.toolbarLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 36)
    }
}

// MARK: - Document Detail (Inspector)

struct DocumentDetailView: View {
    let document: OpenedDocument
    let pdfService: PDFServiceProtocol
    @State private var inspectorVM: InspectorViewModel?

    var body: some View {
        Group {
            if let vm = inspectorVM {
                InspectorView(viewModel: vm)
            } else {
                ProgressView()
            }
        }
        .task(id: document.id) {
            let vm = InspectorViewModel(pdfService: pdfService)
            await vm.loadDocument(document)
            inspectorVM = vm
        }
    }
}

// MARK: - Drop Zone

struct DropZoneView: View {
    let viewModel: AppViewModel

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop PDF files here")
                .font(.title2)
            Text("Or use File > Open to add documents")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(viewModel.isDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }
}
