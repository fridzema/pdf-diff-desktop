import SwiftUI

@main
struct PdfDiffApp: App {
    var body: some Scene {
        WindowGroup {
            AppView(viewModel: AppViewModel(pdfService: MockPDFService()))
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open PDF...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.pdf]
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        // Post notification or use environment to pass URLs
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
