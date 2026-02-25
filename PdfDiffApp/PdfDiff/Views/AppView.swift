import SwiftUI
import UniformTypeIdentifiers

struct AppView: View {
    @State var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarContent(viewModel: viewModel)
        } detail: {
            if let selected = viewModel.selectedDocument {
                Text("Inspector for \(selected.fileName)")
                    .font(.title2)
            } else {
                DropZoneView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
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

struct SidebarContent: View {
    let viewModel: AppViewModel

    var body: some View {
        List(viewModel.documents, selection: Binding(
            get: { viewModel.selectedDocument },
            set: { viewModel.selectedDocument = $0 }
        )) { doc in
            Label(doc.fileName, systemImage: "doc.richtext")
        }
        .navigationTitle("Documents")
    }
}

struct DropZoneView: View {
    let viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
