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
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { NotificationCenter.default.post(name: .zoomIn, object: nil) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { NotificationCenter.default.post(name: .zoomOut, object: nil) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Fit to Window") { NotificationCenter.default.post(name: .zoomFit, object: nil) }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }
    }
}

extension Notification.Name {
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomFit = Notification.Name("zoomFit")
}
