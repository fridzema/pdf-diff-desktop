import SwiftUI

/// Reusable bottom overlay drawer with Liquid Glass backdrop.
/// Slides up from the bottom of its parent, overlaying canvas content.
struct GlassDrawer<Content: View>: View {
    let isPresented: Bool
    let content: Content

    @Namespace private var drawerNamespace

    init(isPresented: Bool, @ViewBuilder content: () -> Content) {
        self.isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        if isPresented {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Drag handle
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.secondary.opacity(0.4))
                        .frame(width: 36, height: 4)
                        .padding(.top, DesignTokens.Spacing.sm)
                        .padding(.bottom, DesignTokens.Spacing.xs)

                    ScrollView {
                        content
                            .padding(.horizontal, DesignTokens.Drawer.horizontalPadding)
                            .padding(.bottom, DesignTokens.Spacing.md)
                    }
                }
                .frame(maxHeight: GlassDrawerConstants.drawerMaxHeight)
                .glassEffect(.regular, in: UnevenRoundedRectangle(
                    topLeadingRadius: DesignTokens.Drawer.cornerRadius,
                    topTrailingRadius: DesignTokens.Drawer.cornerRadius
                ))
                .padding(.horizontal, DesignTokens.Spacing.sm)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

}

private enum GlassDrawerConstants {
    static let drawerMaxHeight: CGFloat = 400
}

/// Variant that reads the parent's geometry to compute 40% max height.
struct GeometricGlassDrawer<Content: View>: View {
    let isPresented: Bool
    let content: Content

    init(isPresented: Bool, @ViewBuilder content: () -> Content) {
        self.isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            GlassDrawerInner(
                isPresented: isPresented,
                maxHeight: geo.size.height * DesignTokens.Drawer.maxHeightRatio,
                content: { content }
            )
        }
    }
}

private struct GlassDrawerInner<Content: View>: View {
    let isPresented: Bool
    let maxHeight: CGFloat
    let content: Content

    init(isPresented: Bool, maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.isPresented = isPresented
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        if isPresented {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.secondary.opacity(0.4))
                        .frame(width: 36, height: 4)
                        .padding(.top, DesignTokens.Spacing.sm)
                        .padding(.bottom, DesignTokens.Spacing.xs)

                    ScrollView {
                        content
                            .padding(.horizontal, DesignTokens.Drawer.horizontalPadding)
                            .padding(.bottom, DesignTokens.Spacing.md)
                    }
                }
                .frame(maxHeight: maxHeight)
                .glassEffect(.regular, in: UnevenRoundedRectangle(
                    topLeadingRadius: DesignTokens.Drawer.cornerRadius,
                    topTrailingRadius: DesignTokens.Drawer.cornerRadius
                ))
                .padding(.horizontal, DesignTokens.Spacing.sm)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
