import SwiftUI

@main
struct PdfDiffApp: App {
    @State private var viewModel = AppViewModel(pdfService: MockPDFService())

    var body: some Scene {
        WindowGroup {
            AppView(viewModel: viewModel)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open PDF...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.pdf]
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        viewModel.openFiles(urls: panel.urls)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
