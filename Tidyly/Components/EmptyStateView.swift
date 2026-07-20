import SwiftUI

struct EmptyStateView: View {
    let icon: String?
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: AppTheme.spacingMd) {
            if let icon {
                ZStack {
                    Circle()
                        .fill(ColorAsset.surfaceAlt.color)
                        .frame(width: 72, height: 72)
                    Image(systemName: icon)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(ColorAsset.primary.color)
                }
            }
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(ColorAsset.text.color)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(ColorAsset.textTertiary.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}
