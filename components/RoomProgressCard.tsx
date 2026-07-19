import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { ProgressRing } from './ProgressRing';
import { Colors, Spacing, FontSizes } from '@/lib/theme';

export function RoomProgressCard({
  name,
  icon,
  color,
  completionRate,
  dueCount,
  overdueCount,
  taskCount,
  onPress,
}: {
  name: string;
  icon: string;
  color: string;
  completionRate: number;
  dueCount: number;
  overdueCount: number;
  taskCount: number;
  onPress?: () => void;
}) {
  return (
    <View style={styles.card}>
      <View style={styles.leftSection}>
        <View style={[styles.iconWrap, { backgroundColor: color + '20' }]}>
          <Text style={styles.icon}>{icon}</Text>
        </View>
        <View style={styles.info}>
          <Text style={styles.name}>{name}</Text>
          <Text style={styles.taskCount}>{taskCount} tasks</Text>
          {overdueCount > 0 ? (
            <View style={[styles.badge, { backgroundColor: 'rgba(239, 68, 68, 0.12)' }]}>
              <Text style={[styles.badgeText, { color: Colors.error }]}>{overdueCount} overdue</Text>
            </View>
          ) : dueCount > 0 ? (
            <View style={[styles.badge, { backgroundColor: 'rgba(245, 158, 11, 0.12)' }]}>
              <Text style={[styles.badgeText, { color: Colors.warning }]}>{dueCount} due today</Text>
            </View>
          ) : (
            <View style={[styles.badge, { backgroundColor: 'rgba(16, 185, 129, 0.12)' }]}>
              <Text style={[styles.badgeText, { color: Colors.success }]}>All caught up</Text>
            </View>
          )}
        </View>
      </View>
      <ProgressRing progress={completionRate / 100} size={56} color={color}>
        <Text style={styles.progressText}>{completionRate}%</Text>
      </ProgressRing>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: Colors.surface,
    borderRadius: 16,
    padding: Spacing.lg,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  leftSection: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    gap: Spacing.md,
  },
  iconWrap: {
    width: 48,
    height: 48,
    borderRadius: 24,
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    fontSize: 24,
  },
  info: {
    flex: 1,
    gap: 2,
  },
  name: {
    fontSize: FontSizes.lg,
    fontWeight: '700',
    color: Colors.text,
  },
  taskCount: {
    fontSize: FontSizes.sm,
    color: Colors.textTertiary,
  },
  badge: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 8,
    alignSelf: 'flex-start',
    marginTop: 4,
  },
  badgeText: {
    fontSize: FontSizes.xs,
    fontWeight: '600',
  },
  progressText: {
    fontSize: FontSizes.sm,
    fontWeight: '700',
    color: Colors.text,
  },
});
