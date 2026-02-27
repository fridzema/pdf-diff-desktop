import SwiftUI

struct ZoomToolbar: View {
    @Binding var zoomLevel: CGFloat
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void
    var onZoomFit: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onZoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Text(String(format: "%.0f%%", zoomLevel * 100))
                .font(.caption.monospacedDigit())
                .frame(width: 44)
                .onTapGesture { onZoomFit() }

            Button(action: onZoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Button("Fit", action: onZoomFit)
                .font(.caption)
                .buttonStyle(.borderless)
        }
    }
}
