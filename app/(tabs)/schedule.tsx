import React, { useState, useCallback, useMemo } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl, TouchableOpacity, Alert } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { ChevronLeft, ChevronRight, Clock, Check } from 'lucide-react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Colors, Spacing, BorderRadius, FontSizes, Shadows } from '@/lib/theme';
import { EmptyState } from '@/components/EmptyState';
import {
  fetchTasksForWeek,
  completeTask,
  todayISO,
  getWeekStart,
  getWeekDates,
  addDays,
  formatFullDate,
  formatRelativeDate,
  daysUntil,
  PRIORITIES,
} from '@/lib/database';
import type { TaskWithRoom } from '@/lib/types';

const DAY_LABELS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

export default function ScheduleScreen() {
  const [weekStart, setWeekStart] = useState(getWeekStart(new Date(), true));
  const [tasks, setTasks] = useState<TaskWithRoom[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [selectedDate, setSelectedDate] = useState(todayISO());
  const [completedIds, setCompletedIds] = useState<Set<string>>(new Set());

  const weekDates = useMemo(() => getWeekDates(weekStart), [weekStart]);
  const today = todayISO();

  const loadData = useCallback(async () => {
    try {
      const data = await fetchTasksForWeek(weekStart);
      setTasks(data);
      // Reset completed set — in a real app we'd check completions for each task
      setCompletedIds(new Set());
    } catch (e) {
      console.error('Failed to load schedule', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [weekStart]);

  useFocusEffect(
    useCallback(() => {
      loadData();
    }, [loadData])
  );

  const onRefresh = () => {
    setRefreshing(true);
    loadData();
  };

  const goPrevWeek = () => setWeekStart(addDays(weekStart, -7));
  const goNextWeek = () => setWeekStart(addDays(weekStart, 7));
  const goThisWeek = () => {
    setWeekStart(getWeekStart(new Date(), true));
    setSelectedDate(today);
  };

  const monthLabel = useMemo(() => {
    const start = new Date(weekStart + 'T00:00:00');
    const end = new Date(addDays(weekStart, 6) + 'T00:00:00');
    if (start.getMonth() === end.getMonth()) {
      return `${MONTH_NAMES[start.getMonth()]} ${start.getFullYear()}`;
    }
    return `${MONTH_NAMES[start.getMonth()]} - ${MONTH_NAMES[end.getMonth()]} ${end.getFullYear()}`;
  }, [weekStart]);

  const tasksForDate = (dateStr: string) =>
    tasks.filter((t) => t.next_due_at === dateStr);

  const tasksForSelected = tasksForDate(selectedDate);
  const pendingSelected = tasksForSelected.filter((t) => !completedIds.has(t.id));
  const completedSelected = tasksForSelected.filter((t) => completedIds.has(t.id));

  const handleComplete = async (task: TaskWithRoom) => {
    try {
      await completeTask(task, today);
      setCompletedIds((prev) => new Set([...prev, task.id]));
      loadData();
    } catch {
      Alert.alert('Error', 'Could not mark task as done.');
    }
  };

  const tasksCountForDate = (dateStr: string) => {
    const count = tasksForDate(dateStr).length;
    if (count === 0) return 0;
    return count;
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <View style={styles.headerRow}>
          <Text style={styles.headerTitle}>Schedule</Text>
          <TouchableOpacity onPress={goThisWeek} style={styles.todayBtn}>
            <Text style={styles.todayBtnText}>Today</Text>
          </TouchableOpacity>
        </View>
        <View style={styles.weekNav}>
          <TouchableOpacity onPress={goPrevWeek} style={styles.navBtn}>
            <ChevronLeft size={22} color={Colors.text} strokeWidth={2.5} />
          </TouchableOpacity>
          <Text style={styles.monthLabel}>{monthLabel}</Text>
          <TouchableOpacity onPress={goNextWeek} style={styles.navBtn}>
            <ChevronRight size={22} color={Colors.text} strokeWidth={2.5} />
          </TouchableOpacity>
        </View>
      </View>

      {/* Week calendar */}
      <View style={styles.weekCalendar}>
        {weekDates.map((date, idx) => {
          const isToday = date === today;
          const isSelected = date === selectedDate;
          const taskCount = tasksCountForDate(date);
          const isPast = date < today;
          const d = new Date(date + 'T00:00:00');
          const dayNum = d.getDate();

          return (
            <TouchableOpacity
              key={date}
              style={[
                styles.dayCell,
                isSelected && styles.dayCellSelected,
              ]}
              onPress={() => setSelectedDate(date)}
            >
              <Text style={[styles.dayLabel, isSelected && styles.dayLabelSelected]}>
                {DAY_LABELS[idx]}
              </Text>
              <Text style={[
                styles.dayNumber,
                isToday && styles.dayNumberToday,
                isSelected && styles.dayNumberSelected,
              ]}>
                {dayNum}
              </Text>
              <View style={styles.dotRow}>
                {taskCount > 0 && (
                  <View style={[
                    styles.taskDot,
                    isPast && !isSelected && styles.taskDotPast,
                    isSelected && styles.taskDotSelected,
                  ]} />
                )}
                {taskCount > 3 && (
                  <View style={[
                    styles.taskDot,
                    isPast && !isSelected && styles.taskDotPast,
                    isSelected && styles.taskDotSelected,
                  ]} />
                )}
              </View>
            </TouchableOpacity>
          );
        })}
      </View>

      {/* Selected date tasks */}
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Text style={styles.selectedDateLabel}>{formatFullDate(selectedDate)}</Text>

        {pendingSelected.length === 0 && completedSelected.length === 0 && (
          <EmptyState
            icon={<Check size={32} color={Colors.success} strokeWidth={2} />}
            title="No tasks due"
            subtitle="Nothing scheduled for this day."
          />
        )}

        <View style={styles.taskList}>
          {pendingSelected.map((task) => {
            const priority = PRIORITIES[task.priority];
            const isOverdue = task.next_due_at < today;
            return (
              <TouchableOpacity
                key={task.id}
                style={styles.taskRow}
                onPress={() => handleComplete(task)}
                activeOpacity={0.7}
              >
                <View style={[styles.checkCircle, { borderColor: Colors.borderDark }]} />
                <View style={styles.taskContent}>
                  <Text style={styles.taskTitle}>{task.title}</Text>
                  <View style={styles.taskMeta}>
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
                {isOverdue && (
                  <View style={[styles.dueBadge, styles.overdueBadge]}>
                    <Text style={[styles.dueText, styles.overdueText]}>Overdue</Text>
                  </View>
                )}
              </TouchableOpacity>
            );
          })}

          {completedSelected.map((task) => (
            <View key={task.id} style={[styles.taskRow, styles.completedRow]}>
              <View style={[styles.checkCircle, styles.checkedCircle]}>
                <Check size={16} color={Colors.textInverse} strokeWidth={3} />
              </View>
              <View style={styles.taskContent}>
                <Text style={styles.completedTitle}>{task.title}</Text>
                <View style={[styles.roomTag, { backgroundColor: task.rooms.color + '20' }]}>
                  <Text style={styles.roomTagIcon}>{task.rooms.icon}</Text>
                  <Text style={[styles.roomTagText, { color: task.rooms.color }]}>{task.rooms.name}</Text>
                </View>
              </View>
            </View>
          ))}
        </View>

        <View style={{ height: 40 }} />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  header: {
    paddingHorizontal: Spacing.xl,
    paddingTop: Spacing.xl,
    paddingBottom: Spacing.md,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerTitle: {
    fontSize: FontSizes.xxxl,
    fontWeight: '800',
    color: Colors.text,
  },
  todayBtn: {
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.sm,
    borderRadius: BorderRadius.pill,
    backgroundColor: Colors.primaryLight,
  },
  todayBtnText: {
    fontSize: FontSizes.sm,
    fontWeight: '600',
    color: Colors.primary,
  },
  weekNav: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: Spacing.md,
  },
  navBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: Colors.surfaceAlt,
    alignItems: 'center',
    justifyContent: 'center',
  },
  monthLabel: {
    fontSize: FontSizes.lg,
    fontWeight: '700',
    color: Colors.text,
  },
  weekCalendar: {
    flexDirection: 'row',
    paddingHorizontal: Spacing.md,
    paddingBottom: Spacing.md,
    gap: 4,
  },
  dayCell: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: Spacing.md,
    borderRadius: BorderRadius.lg,
    gap: 4,
  },
  dayCellSelected: {
    backgroundColor: Colors.primary,
    ...Shadows.md,
  },
  dayLabel: {
    fontSize: FontSizes.xs,
    fontWeight: '600',
    color: Colors.textTertiary,
    textTransform: 'uppercase',
  },
  dayLabelSelected: {
    color: 'rgba(255, 255, 255, 0.8)',
  },
  dayNumber: {
    fontSize: FontSizes.lg,
    fontWeight: '700',
    color: Colors.text,
  },
  dayNumberToday: {
    color: Colors.primary,
  },
  dayNumberSelected: {
    color: Colors.textInverse,
  },
  dotRow: {
    flexDirection: 'row',
    gap: 3,
    height: 8,
  alignItems: 'center',
  },
  taskDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: Colors.primary,
  },
  taskDotPast: {
    backgroundColor: Colors.textTertiary,
  },
  taskDotSelected: {
    backgroundColor: Colors.textInverse,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: Spacing.xl,
    paddingTop: Spacing.md,
  },
  selectedDateLabel: {
    fontSize: FontSizes.md,
    fontWeight: '600',
    color: Colors.textSecondary,
    marginBottom: Spacing.lg,
  },
  taskList: {
    gap: Spacing.md,
  },
  taskRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
    backgroundColor: Colors.surface,
    borderRadius: BorderRadius.lg,
    padding: Spacing.lg,
    borderWidth: 1,
    borderColor: Colors.border,
    ...Shadows.sm,
  },
  completedRow: {
    opacity: 0.5,
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
  taskContent: {
    flex: 1,
    gap: 4,
  },
  taskTitle: {
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
  taskMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
    flexWrap: 'wrap',
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
  dueBadge: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 10,
    backgroundColor: Colors.surfaceAlt,
  },
  overdueBadge: {
    backgroundColor: 'rgba(239, 68, 68, 0.12)',
  },
  dueText: {
    fontSize: FontSizes.xs,
    fontWeight: '600',
    color: Colors.textSecondary,
  },
  overdueText: {
    color: Colors.error,
  },
});
