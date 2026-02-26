import SwiftUI

struct SideBySideView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?
    let leftLabel: String?
    let rightLabel: String?
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    @State private var optionHeld = false
    @State private var hoveredPanel: Panel? = nil
    @State private var monitor: Any? = nil

    enum Panel { case left, right }

    var body: some View {
        HStack(spacing: 1) {
            panelView(image: leftImage, label: leftLabel, panel: .left)
            Divider()
            panelView(image: rightImage, label: rightLabel, panel: .right)
        }
        .onAppear { installModifierMonitor() }
        .onDisappear { removeModifierMonitor() }
    }

    private func panelView(image: NSImage?, label: String?, panel: Panel) -> some View {
        let isIndependent = optionHeld && hoveredPanel == panel

        return VStack(spacing: 0) {
            if let label {
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isIndependent {
                        Image(systemName: "lock.open.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }

            ZoomableContainer(zoom: $zoomLevel, offset: $panOffset, isIndependent: isIndependent) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Text("No page")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onHover { hovering in
                hoveredPanel = hovering ? panel : nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Modifier key monitoring

    private func installModifierMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            optionHeld = event.modifierFlags.contains(.option)
            return event
        }
    }

    private func removeModifierMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
