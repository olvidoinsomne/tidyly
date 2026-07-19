import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl, TouchableOpacity, Alert } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { Plus, Sparkles, TrendingUp, Flame, Clock } from 'lucide-react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Colors, Spacing, BorderRadius, FontSizes, Shadows } from '@/lib/theme';
import { TaskCard } from '@/components/TaskCard';
import { EmptyState } from '@/components/EmptyState';
import { ProgressRing } from '@/components/ProgressRing';
import { TaskEditor } from '@/components/TaskEditor';
import {
  fetchTasksForDate,
  fetchRooms,
  completeTask,
  undoCompletion,
  fetchCompletionByTaskAndDate,
  todayISO,
  formatFullDate,
} from '@/lib/database';
import type { TaskWithRoom, Room } from '@/lib/types';

export default function HomeScreen() {
  const [tasks, setTasks] = useState<TaskWithRoom[]>([]);
  const [rooms, setRooms] = useState<Room[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [completedTaskIds, setCompletedTaskIds] = useState<Set<string>>(new Set());
  const [completionIds, setCompletionIds] = useState<Record<string, string>>({});
  const [showAddTask, setShowAddTask] = useState(false);

  const today = todayISO();

  const loadData = useCallback(async () => {
    try {
      const [todayTasks, allRooms] = await Promise.all([
        fetchTasksForDate(today),
        fetchRooms(),
      ]);
      setTasks(todayTasks);
      setRooms(allRooms);

      const done = new Set<string>();
      const compIds: Record<string, string> = {};
      for (const t of todayTasks) {
        const comp = await fetchCompletionByTaskAndDate(t.id, today);
        if (comp) {
          done.add(t.id);
          compIds[t.id] = comp.id;
        }
      }
      setCompletedTaskIds(done);
      setCompletionIds(compIds);
    } catch (e) {
      console.error('Failed to load tasks', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [today]);

  useFocusEffect(
    useCallback(() => {
      loadData();
    }, [loadData])
  );

  const onRefresh = () => {
    setRefreshing(true);
    loadData();
  };

  const handleComplete = async (task: TaskWithRoom) => {
    try {
      await completeTask(task, today);
      setCompletedTaskIds((prev) => new Set([...prev, task.id]));
      const comp = await fetchCompletionByTaskAndDate(task.id, today);
      if (comp) {
        setCompletionIds((prev) => ({ ...prev, [task.id]: comp.id }));
      }
    } catch {
      Alert.alert('Error', 'Could not mark task as done.');
    }
  };

  const handleUndo = async (task: TaskWithRoom) => {
    const compId = completionIds[task.id];
    if (!compId) return;
    try {
      await undoCompletion(task, compId);
      setCompletedTaskIds((prev) => {
        const next = new Set(prev);
        next.delete(task.id);
        return next;
      });
    } catch {
      Alert.alert('Error', 'Could not undo completion.');
    }
  };

  const pendingTasks = tasks.filter((t) => !completedTaskIds.has(t.id));
  const completedTasks = tasks.filter((t) => completedTaskIds.has(t.id));
  const totalTasks = tasks.length;
  const completionRate = totalTasks > 0 ? completedTasks.length / totalTasks : 0;
  const totalMinutes = pendingTasks.reduce((sum, t) => sum + t.estimated_minutes, 0);
  const overdueCount = pendingTasks.filter((t) => t.next_due_at < today).length;

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        {/* Header */}
        <View style={styles.header}>
          <View>
            <Text style={styles.dateText}>{formatFullDate(today)}</Text>
            <Text style={styles.greeting}>Let's get cleaning!</Text>
          </View>
          <ProgressRing progress={completionRate} size={64} strokeWidth={7}>
            <Text style={styles.ringPercent}>{Math.round(completionRate * 100)}%</Text>
          </ProgressRing>
        </View>

        {/* Summary cards */}
        <View style={styles.summaryRow}>
          <View style={styles.summaryCard}>
            <View style={[styles.summaryIcon, { backgroundColor: 'rgba(59, 130, 246, 0.12)' }]}>
              <Clock size={20} color={Colors.primary} strokeWidth={2} />
            </View>
            <View>
              <Text style={styles.summaryValue}>{totalMinutes}m</Text>
              <Text style={styles.summaryLabel}>Remaining</Text>
            </View>
          </View>
          <View style={styles.summaryCard}>
            <View style={[styles.summaryIcon, { backgroundColor: 'rgba(245, 158, 11, 0.12)' }]}>
              <Flame size={20} color={Colors.warning} strokeWidth={2} />
            </View>
            <View>
              <Text style={styles.summaryValue}>{overdueCount}</Text>
              <Text style={styles.summaryLabel}>Overdue</Text>
            </View>
          </View>
          <View style={styles.summaryCard}>
            <View style={[styles.summaryIcon, { backgroundColor: 'rgba(16, 185, 129, 0.12)' }]}>
              <TrendingUp size={20} color={Colors.success} strokeWidth={2} />
            </View>
            <View>
              <Text style={styles.summaryValue}>{completedTasks.length}</Text>
              <Text style={styles.summaryLabel}>Done</Text>
            </View>
          </View>
        </View>

        {/* Pending tasks */}
        <View style={styles.sectionHeader}>
          <Text style={styles.sectionTitle}>To Do</Text>
          <Text style={styles.sectionCount}>{pendingTasks.length} tasks</Text>
        </View>

        {pendingTasks.length === 0 && completedTasks.length === 0 && !loading && (
          <EmptyState
            icon={<Sparkles size={32} color={Colors.primary} strokeWidth={2} />}
            title="All done for today!"
            subtitle="No tasks due. Enjoy your clean home."
          />
        )}

        {pendingTasks.length === 0 && completedTasks.length > 0 && (
          <View style={styles.allDoneCard}>
            <Sparkles size={28} color={Colors.success} strokeWidth={2} />
            <Text style={styles.allDoneTitle}>All tasks done!</Text>
            <Text style={styles.allDoneSubtitle}>Great job keeping your home clean.</Text>
          </View>
        )}

        <View style={styles.taskList}>
          {pendingTasks.map((task) => (
            <TaskCard
              key={task.id}
              task={task}
              onComplete={() => handleComplete(task)}
              onLongPress={() => {}}
            />
          ))}
        </View>

        {/* Completed tasks */}
        {completedTasks.length > 0 && (
          <>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>Completed</Text>
              <Text style={styles.sectionCount}>{completedTasks.length} done</Text>
            </View>
            <View style={styles.taskList}>
              {completedTasks.map((task) => (
                <TaskCard
                  key={task.id}
                  task={task}
                  completed
                  onUndo={() => handleUndo(task)}
                />
              ))}
            </View>
          </>
        )}

        <View style={{ height: 100 }} />
      </ScrollView>

      {/* FAB */}
      <TouchableOpacity
        style={styles.fab}
        onPress={() => setShowAddTask(true)}
        activeOpacity={0.8}
      >
        <Plus size={26} color={Colors.textInverse} strokeWidth={2.5} />
      </TouchableOpacity>

      <TaskEditor
        visible={showAddTask}
        onClose={() => setShowAddTask(false)}
        onSaved={loadData}
        room={rooms[0] ?? { id: '', name: '', icon: '🧹', color: Colors.primary, sort_order: 0, created_at: '' }}
        rooms={rooms}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: Spacing.xl,
    paddingTop: Spacing.xl,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: Spacing.xl,
  },
  dateText: {
    fontSize: FontSizes.sm,
    color: Colors.textTertiary,
    fontWeight: '500',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  greeting: {
    fontSize: FontSizes.xxxl,
    fontWeight: '800',
    color: Colors.text,
    marginTop: 2,
  },
  ringPercent: {
    fontSize: FontSizes.sm,
    fontWeight: '700',
    color: Colors.primary,
  },
  summaryRow: {
    flexDirection: 'row',
    gap: Spacing.md,
    marginBottom: Spacing.xxl,
  },
  summaryCard: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
    backgroundColor: Colors.surface,
    borderRadius: BorderRadius.lg,
    padding: Spacing.md,
    borderWidth: 1,
    borderColor: Colors.border,
    ...Shadows.sm,
  },
  summaryIcon: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  summaryValue: {
    fontSize: FontSizes.xl,
    fontWeight: '700',
    color: Colors.text,
  },
  summaryLabel: {
    fontSize: FontSizes.xs,
    color: Colors.textTertiary,
    fontWeight: '500',
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: Spacing.md,
  },
  sectionTitle: {
    fontSize: FontSizes.xl,
    fontWeight: '700',
    color: Colors.text,
  },
  sectionCount: {
    fontSize: FontSizes.sm,
    color: Colors.textTertiary,
    fontWeight: '500',
  },
  taskList: {
    gap: Spacing.md,
  },
  allDoneCard: {
    alignItems: 'center',
    gap: Spacing.sm,
    backgroundColor: Colors.surface,
    borderRadius: BorderRadius.xl,
    padding: Spacing.xxl,
    borderWidth: 1,
    borderColor: Colors.border,
    marginBottom: Spacing.md,
  },
  allDoneTitle: {
    fontSize: FontSizes.lg,
    fontWeight: '700',
    color: Colors.text,
  },
  allDoneSubtitle: {
    fontSize: FontSizes.sm,
    color: Colors.textTertiary,
  },
  fab: {
    position: 'absolute',
    bottom: 80,
    right: Spacing.xl,
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: Colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
    ...Shadows.lg,
  },
});
