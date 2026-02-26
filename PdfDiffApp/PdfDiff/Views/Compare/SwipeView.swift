import SwiftUI

struct SwipeView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    @State private var dividerPosition: CGFloat = 0.5

    var body: some View {
        ZoomableContainer(zoom: $zoomLevel, offset: $panOffset) {
            GeometryReader { geometry in
                let dividerX = geometry.size.width * dividerPosition

                ZStack {
                    // Right image (full width, underneath)
                    if let rightImage {
                        Image(nsImage: rightImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }

                    // Left image (clipped to divider position)
                    if let leftImage {
                        Image(nsImage: leftImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipShape(
                                HorizontalClip(width: dividerX)
                            )
                    }

                    // Divider line
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: geometry.size.height)
                        .position(x: dividerX, y: geometry.size.height / 2)

                    // Drag handle — use .highPriorityGesture so it overrides pan
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .position(x: dividerX, y: geometry.size.height / 2)
                        .highPriorityGesture(
                            DragGesture()
                                .onChanged { value in
                                    dividerPosition = max(0.05, min(0.95, value.location.x / geometry.size.width))
                                }
                        )

                    // Labels
                    VStack {
                        HStack {
                            Text("Left")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(8)
                            Spacer()
                            Text("Right")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}

/// Clips content to the left side up to a given width.
struct HorizontalClip: Shape {
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: 0, y: 0, width: width, height: rect.height))
    }
}
