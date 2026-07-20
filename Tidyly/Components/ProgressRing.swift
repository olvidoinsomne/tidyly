import SwiftUI

struct ProgressRing<Content: View>: View {
    let progress: Double
    var size: CGFloat = 56
    var strokeWidth: CGFloat = 6
    var color: Color = ColorAsset.primary.color
    var trackColor: Color = ColorAsset.border.color
    var content: () -> Content

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: strokeWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: clamped)
            content()
        }
        .frame(width: size, height: size)
    }
}

extension ProgressRing where Content == EmptyView {
    init(progress: Double, size: CGFloat = 56, strokeWidth: CGFloat = 6, color: Color = ColorAsset.primary.color, trackColor: Color = ColorAsset.border.color) {
        self.progress = progress
        self.size = size
        self.strokeWidth = strokeWidth
        self.color = color
        self.trackColor = trackColor
        self.content = { EmptyView() }
    }
}
