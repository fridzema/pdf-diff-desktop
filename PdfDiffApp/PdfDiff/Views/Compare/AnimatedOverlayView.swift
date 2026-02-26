import SwiftUI

struct AnimatedOverlayView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    @State private var showingLeft = true
    @State private var isPlaying = true
    @State private var blinkInterval: Double = 0.8

    // Timer-driven animation
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Blink canvas
            ZoomableContainer(zoom: $zoomLevel, offset: $panOffset) {
                ZStack {
                    if showingLeft, let leftImage {
                        Image(nsImage: leftImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else if !showingLeft, let rightImage {
                        Image(nsImage: rightImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Text("No images to compare")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Blink controls
            blinkControls
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
        .onChange(of: isPlaying) { _, playing in
            if playing { startTimer() } else { stopTimer() }
        }
        .onChange(of: blinkInterval) { _, _ in
            if isPlaying {
                stopTimer()
                startTimer()
            }
        }
    }

    private var blinkControls: some View {
        HStack(spacing: 16) {
            // Play/Pause
            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)
            .frame(width: 24)

            // Manual toggle (when paused)
            if !isPlaying {
                HStack(spacing: 4) {
                    Button {
                        showingLeft = true
                    } label: {
                        Text("Left")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(showingLeft ? Color.accentColor : Color.clear)
                            .foregroundStyle(showingLeft ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingLeft = false
                    } label: {
                        Text("Right")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(!showingLeft ? Color.accentColor : Color.clear)
                            .foregroundStyle(!showingLeft ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Speed control
            HStack(spacing: 8) {
                Text("Speed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $blinkInterval, in: 0.3...2.0)
                    .frame(width: 100)
                Text(String(format: "%.1fs", blinkInterval))
                    .font(.caption.monospacedDigit())
                    .frame(width: 30)
            }

            // Current side indicator
            Text(showingLeft ? "Left" : "Right")
                .font(.caption.bold())
                .foregroundStyle(showingLeft ? .blue : .orange)
                .frame(width: 36)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: blinkInterval, repeats: true) { _ in
            DispatchQueue.main.async {
                showingLeft.toggle()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
