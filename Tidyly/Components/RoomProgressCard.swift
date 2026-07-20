import SwiftUI

struct RoomProgressCard: View {
    let room: Room
    let completionRate: Int
    let dueCount: Int
    let overdueCount: Int
    let taskCount: Int

    var body: some View {
        HStack(spacing: AppTheme.spacingMd) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(hex: room.color).opacity(0.15))
                    .frame(width: 48, height: 48)
                Text(room.icon)
                    .font(.system(size: 24))
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(ColorAsset.text.color)

                Text("\(taskCount) tasks")
                    .font(.system(size: 13))
                    .foregroundColor(ColorAsset.textTertiary.color)

                // Badge
                Group {
                    if overdueCount > 0 {
                        Text("\(overdueCount) overdue")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ColorAsset.error.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ColorAsset.error.color.opacity(0.12))
                            .cornerRadius(8)
                    } else if dueCount > 0 {
                        Text("\(dueCount) due today")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ColorAsset.warning.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ColorAsset.warning.color.opacity(0.12))
                            .cornerRadius(8)
                    } else {
                        Text("All caught up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ColorAsset.success.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ColorAsset.success.color.opacity(0.12))
                            .cornerRadius(8)
                    }
                }
                .padding(.top, 2)
            }

            Spacer()

            // Progress ring
            ProgressRing(progress: Double(completionRate) / 100.0, size: 56, color: Color(hex: room.color)) {
                Text("\(completionRate)%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(ColorAsset.text.color)
            }
        }
        .padding(AppTheme.spacingLg)
        .background(ColorAsset.surface.color)
        .cornerRadius(AppTheme.cornerLg)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerLg)
                .stroke(ColorAsset.border.color, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}
