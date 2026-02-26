import SwiftUI

struct ZoomableContainer<Content: View>: View {
    let content: Content

    // External bindings (for synced mode) or internal state (standalone)
    @Binding var externalZoom: CGFloat
    @Binding var externalOffset: CGSize
    let useExternalState: Bool

    // Independence toggle (for Option-key decouple in side-by-side)
    var isIndependent: Bool = false

    // Internal state (standalone mode)
    @State private var internalZoom: CGFloat = 1.0
    @State private var internalOffset: CGSize = .zero

    // Independent state (decoupled mode)
    @State private var independentZoom: CGFloat = 1.0
    @State private var independentOffset: CGSize = .zero

    // Gesture tracking
    @State private var lastMagnification: CGFloat = 1.0
    @State private var dragStart: CGSize = .zero

    // Zoom range
    private let minZoom: CGFloat = 0.1
    private let maxZoom: CGFloat = 10.0

    /// Standalone initializer (no external bindings)
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self._externalZoom = .constant(1.0)
        self._externalOffset = .constant(.zero)
        self.useExternalState = false
    }

    /// Synced initializer (external bindings) with optional independence toggle
    init(
        zoom: Binding<CGFloat>,
        offset: Binding<CGSize>,
        isIndependent: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self._externalZoom = zoom
        self._externalOffset = offset
        self.useExternalState = true
        self.isIndependent = isIndependent
    }

    private var currentZoom: CGFloat {
        if isIndependent { return independentZoom }
        return useExternalState ? externalZoom : internalZoom
    }

    private var currentOffset: CGSize {
        if isIndependent { return independentOffset }
        return useExternalState ? externalOffset : internalOffset
    }

    private func setZoom(_ value: CGFloat) {
        let clamped = min(maxZoom, max(minZoom, value))
        if isIndependent {
            independentZoom = clamped
        } else if useExternalState {
            externalZoom = clamped
        } else {
            internalZoom = clamped
        }
    }

    private func setOffset(_ value: CGSize) {
        if isIndependent {
            independentOffset = value
        } else if useExternalState {
            externalOffset = value
        } else {
            internalOffset = value
        }
    }

    var body: some View {
        GeometryReader { geometry in
            content
                .scaleEffect(currentZoom, anchor: .center)
                .offset(currentOffset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(magnifyGesture)
                .gesture(panGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if currentZoom > 1.05 {
                            setZoom(1.0)
                            setOffset(.zero)
                            dragStart = .zero
                        } else {
                            setZoom(2.0)
                        }
                    }
                }
        }
        .onChange(of: isIndependent) { wasIndependent, nowIndependent in
            if nowIndependent {
                // Entering independent mode: snapshot current shared state
                independentZoom = useExternalState ? externalZoom : internalZoom
                independentOffset = useExternalState ? externalOffset : internalOffset
                dragStart = independentOffset
            } else {
                // Leaving independent mode: sync dragStart back to shared state
                dragStart = useExternalState ? externalOffset : internalOffset
            }
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / lastMagnification
                setZoom(currentZoom * delta)
                lastMagnification = value.magnification
            }
            .onEnded { _ in
                lastMagnification = 1.0
                if currentZoom <= 1.0 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        setZoom(1.0)
                        setOffset(.zero)
                        dragStart = .zero
                    }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard currentZoom > 1.0 else { return }
                setOffset(CGSize(
                    width: dragStart.width + value.translation.width,
                    height: dragStart.height + value.translation.height
                ))
            }
            .onEnded { _ in
                dragStart = currentOffset
            }
    }
}
