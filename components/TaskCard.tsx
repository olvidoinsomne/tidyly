import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { Check, Clock, RotateCcw } from 'lucide-react-native';
import { Colors, Spacing, BorderRadius, FontSizes, Shadows } from '@/lib/theme';
import { PRIORITIES, formatRelativeDate, daysUntil } from '@/lib/database';
import type { TaskWithRoom } from '@/lib/types';

export function TaskCard({
  task,
  onComplete,
  onUndo,
  onLongPress,
  completed = false,
}: {
  task: TaskWithRoom;
  onComplete?: () => void;
  onUndo?: () => void;
  onLongPress?: () => void;
  completed?: boolean;
}) {
  const priority = PRIORITIES[task.priority];
  const dueStatus = daysUntil(task.next_due_at);
  const isOverdue = dueStatus < 0;
  const isDueToday = dueStatus === 0;

  if (completed) {
    return (
      <View style={[styles.container, styles.completedContainer]}>
        <View style={[styles.checkCircle, styles.checkedCircle]}>
          <Check size={18} color={Colors.textInverse} strokeWidth={3} />
        </View>
        <View style={styles.content}>
          <Text style={styles.completedTitle}>{task.title}</Text>
          <View style={styles.completedMeta}>
            <View style={[styles.roomTag, { backgroundColor: task.rooms.color + '20' }]}>
              <Text style={styles.roomTagIcon}>{task.rooms.icon}</Text>
              <Text style={[styles.roomTagText, { color: task.rooms.color }]}>{task.rooms.name}</Text>
            </View>
            <Text style={styles.doneLabel}>Done today</Text>
          </View>
        </View>
        {onUndo && (
          <TouchableOpacity onPress={onUndo} style={styles.undoBtn} hitSlop={8}>
            <RotateCcw size={18} color={Colors.textTertiary} strokeWidth={2} />
          </TouchableOpacity>
        )}
      </View>
    );
  }

  return (
    <TouchableOpacity
      style={styles.container}
      onPress={onComplete}
      onLongPress={onLongPress}
      activeOpacity={0.7}
    >
      <View style={[styles.checkCircle, { borderColor: Colors.borderDark }]} />
      <View style={styles.content}>
        <Text style={styles.title}>{task.title}</Text>
        <View style={styles.meta}>
          <View style={[styles.roomTag, { backgroundColor: task.rooms.color + '20' }]}>
            <Text style={styles.roomTagIcon}>{task.rooms.icon}</Text>
            <Text style={[styles.roomTagText, { color: task.rooms.color }]}>{task.rooms.name}</Text>
          </View>
          <View style={[styles.priorityTag, { backgroundColor: priority.bgColor }]}>
            <View style={[styles.priorityDot, { backgroundColor: priority.color }]} />
            <Text style={[styles.priorityText, { color: priority.color }]}>{priority.label}</Text>
          </View>
          <View style={styles.timeTag}>
            <Clock size={12} color={Colors.textTertiary} strokeWidth={2} />
            <Text style={styles.timeText}>{task.estimated_minutes}m</Text>
          </View>
        </View>
      </View>
      <View style={styles.rightSection}>
        <View style={[styles.dueBadge, isOverdue && styles.overdueBadge, isDueToday && styles.dueTodayBadge]}>
          <Text style={[styles.dueText, isOverdue && styles.overdueText, isDueToday && styles.dueTodayText]}>
            {formatRelativeDate(task.next_due_at)}
          </Text>
        </View>
      </View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surface,
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    gap: Spacing.md,
    borderWidth: 1,
    borderColor: Colors.border,
    ...Shadows.sm,
  },
  completedContainer: {
    opacity: 0.6,
  },
  checkCircle: {
    width: 28,
    height: 28,
    borderRadius: 14,
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkedCircle: {
    backgroundColor: Colors.success,
    borderColor: Colors.success,
  },
  content: {
    flex: 1,
    gap: Spacing.xs,
  },
  title: {
    fontSize: FontSizes.md,
    fontWeight: '600',
    color: Colors.text,
  },
  completedTitle: {
    fontSize: FontSizes.md,
    fontWeight: '600',
    color: Colors.textTertiary,
    textDecorationLine: 'line-through',
  },
  meta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
    flexWrap: 'wrap',
  },
  completedMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  roomTag: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 8,
  },
  roomTagIcon: {
    fontSize: 12,
  },
  roomTagText: {
    fontSize: FontSizes.xs,
    fontWeight: '600',
  },
  priorityTag: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 8,
  },
  priorityDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
  },
  priorityText: {
    fontSize: FontSizes.xs,
    fontWeight: '600',
  },
  timeTag: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
  },
  timeText: {
    fontSize: FontSizes.xs,
    color: Colors.textTertiary,
    fontWeight: '500',
  },
  rightSection: {
    alignItems: 'flex-end',
  },
  dueBadge: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 10,
    backgroundColor: Colors.surfaceAlt,
  },
  overdueBadge: {
    backgroundColor: 'rgba(239, 68, 68, 0.12)',
  },
  dueTodayBadge: {
    backgroundColor: 'rgba(59, 130, 246, 0.12)',
  },
  dueText: {
    fontSize: FontSizes.xs,
    fontWeight: '600',
    color: Colors.textSecondary,
  },
  overdueText: {
    color: Colors.error,
  },
  dueTodayText: {
    color: Colors.primary,
  },
  undoBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  doneLabel: {
    fontSize: FontSizes.xs,
    color: Colors.success,
    fontWeight: '600',
  },
});
