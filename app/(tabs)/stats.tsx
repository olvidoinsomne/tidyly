import React, { useState, useCallback, useMemo } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl, Dimensions } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { Flame, Trophy, Clock, CheckCircle, TrendingUp, Calendar } from 'lucide-react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Colors, Spacing, BorderRadius, FontSizes, Shadows } from '@/lib/theme';
import { StatCard } from '@/components/StatCard';
import { EmptyState } from '@/components/EmptyState';
import {
  fetchCompletionsInRange,
  fetchAllTasks,
  fetchRooms,
  todayISO,
  addDays,
  getWeekStart,
  getWeekDates,
} from '@/lib/database';
import type { Completion, Task, Room } from '@/lib/types';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const BAR_WIDTH = (SCREEN_WIDTH - Spacing.xl * 2 - Spacing.sm * 6) / 7;

export default function StatsScreen() {
  const [completions, setCompletions] = useState<Completion[]>([]);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [rooms, setRooms] = useState<Room[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const today = todayISO();
  const weekStart = getWeekStart(new Date(), true);
  const weekDates = useMemo(() => getWeekDates(weekStart), [weekStart]);
  const fourWeeksAgo = addDays(today, -28);

  const loadData = useCallback(async () => {
    try {
      const [comps, allTasks, allRooms] = await Promise.all([
        fetchCompletionsInRange(fourWeeksAgo, today),
        fetchAllTasks(),
        fetchRooms(),
      ]);
      setCompletions(comps);
      setTasks(allTasks);
      setRooms(allRooms);
    } catch (e) {
      console.error('Failed to load stats', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [fourWeeksAgo, today]);

  useFocusEffect(
    useCallback(() => {
      loadData();
    }, [loadData])
  );

  const onRefresh = () => {
    setRefreshing(true);
    loadData();
  };

  // Stats calculations
  const todayCompletions = completions.filter((c) => c.completed_at === today).length;
  const weekCompletions = completions.filter((c) => c.completed_at >= weekStart).length;
  const totalCompletions = completions.length;
  const totalMinutes = completions.reduce((sum, c) => {
    const task = tasks.find((t) => t.id === c.task_id);
    return sum + (task?.estimated_minutes ?? 0);
  }, 0);

  // Streak calculation
  const streak = useMemo(() => {
    const dates = new Set(completions.map((c) => c.completed_at));
    let streakCount = 0;
    let checkDate = today;
    while (dates.has(checkDate)) {
      streakCount++;
      checkDate = addDays(checkDate, -1);
    }
    return streakCount;
  }, [completions, today]);

  // Best streak
  const bestStreak = useMemo(() => {
    const sortedDates = [...new Set(completions.map((c) => c.completed_at))].sort();
    if (sortedDates.length === 0) return 0;
    let best = 1;
    let current = 1;
    for (let i = 1; i < sortedDates.length; i++) {
      if (sortedDates[i] === addDays(sortedDates[i - 1], 1)) {
        current++;
        best = Math.max(best, current);
      } else {
        current = 1;
      }
    }
    return best;
  }, [completions]);

  // Weekly bar chart data
  const weekBarData = useMemo(() => {
    return weekDates.map((date) => {
      const count = completions.filter((c) => c.completed_at === date).length;
      return { date, count };
    });
  }, [completions, weekDates]);

  const maxBarCount = Math.max(...weekBarData.map((d) => d.count), 1);

  // Per-room completions
  const roomStats = useMemo(() => {
    return rooms
      .map((room) => {
        const roomCompletions = completions.filter((c) => c.room_id === room.id).length;
        const roomTasks = tasks.filter((t) => t.room_id === room.id).length;
        return { room, completions: roomCompletions, tasks: roomTasks };
      })
      .sort((a, b) => b.completions - a.completions);
  }, [completions, tasks, rooms]);

  const maxRoomCompletions = Math.max(...roomStats.map((r) => r.completions), 1);

  // Completion rate
  const completionRate = tasks.length > 0
    ? Math.round((totalCompletions / tasks.length) * 100)
    : 0;

  const DAY_LABELS = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Statistics</Text>
        <Text style={styles.headerSubtitle}>Your cleaning progress</Text>
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        {/* Top stats row */}
        <View style={styles.topStatsRow}>
          <View style={styles.streakCard}>
            <View style={[styles.streakIcon, { backgroundColor: 'rgba(245, 158, 11, 0.12)' }]}>
              <Flame size={28} color={Colors.warning} strokeWidth={2.5} />
            </View>
            <Text style={styles.streakValue}>{streak}</Text>
            <Text style={styles.streakLabel}>Day Streak</Text>
          </View>
          <View style={styles.streakCard}>
            <View style={[styles.streakIcon, { backgroundColor: 'rgba(16, 185, 129, 0.12)' }]}>
              <Trophy size={28} color={Colors.success} strokeWidth={2.5} />
            </View>
            <Text style={styles.streakValue}>{bestStreak}</Text>
            <Text style={styles.streakLabel}>Best Streak</Text>
          </View>
        </View>

        {/* Stat cards */}
        <View style={styles.statCardsRow}>
          <StatCard
            label="Done Today"
            value={todayCompletions}
            icon={<CheckCircle size={28} color={Colors.primary} strokeWidth={2} />}
          />
          <StatCard
            label="This Week"
            value={weekCompletions}
            icon={<Calendar size={28} color={Colors.secondary} strokeWidth={2} />}
          />
          <StatCard
            label="Total"
            value={totalCompletions}
            icon={<TrendingUp size={28} color={Colors.accent} strokeWidth={2} />}
          />
          <StatCard
            label="Time Spent"
            value={`${Math.round(totalMinutes / 60)}h`}
            sublabel={`${totalMinutes} min total`}
            icon={<Clock size={28} color={Colors.success} strokeWidth={2} />}
          />
        </View>

        {/* Weekly bar chart */}
        <View style={styles.chartCard}>
          <Text style={styles.chartTitle}>This Week</Text>
          <View style={styles.barChart}>
            {weekBarData.map((d, idx) => {
              const heightPct = d.count / maxBarCount;
              const isToday = d.date === today;
              return (
                <View key={d.date} style={styles.barCol}>
                  <View style={styles.barTrack}>
                    <View
                      style={[
                        styles.bar,
                        {
                          height: `${Math.max(heightPct * 100, d.count > 0 ? 8 : 0)}%`,
                          backgroundColor: isToday ? Colors.primary : Colors.primaryLight,
                        },
                      ]}
                    />
                  </View>
                  <Text style={[styles.barLabel, isToday && styles.barLabelToday]}>
                    {DAY_LABELS[idx]}
                  </Text>
                  {d.count > 0 && (
                    <Text style={[styles.barCount, isToday && styles.barCountToday]}>{d.count}</Text>
                  )}
                </View>
              );
            })}
          </View>
        </View>

        {/* Room breakdown */}
        <View style={styles.chartCard}>
          <Text style={styles.chartTitle}>By Room</Text>
          {roomStats.length === 0 ? (
            <Text style={styles.emptyText}>No rooms yet.</Text>
          ) : (
            <View style={styles.roomBars}>
              {roomStats.map((rs) => (
                <View key={rs.room.id} style={styles.roomBarRow}>
                  <View style={styles.roomBarInfo}>
                    <Text style={styles.roomBarIcon}>{rs.room.icon}</Text>
                    <Text style={styles.roomBarName}>{rs.room.name}</Text>
                  </View>
                  <View style={styles.roomBarTrack}>
                    <View
                      style={[
                        styles.roomBar,
                        {
                          width: `${(rs.completions / maxRoomCompletions) * 100}%`,
                          backgroundColor: rs.room.color,
                        },
                      ]}
                    />
                  </View>
                  <Text style={styles.roomBarCount}>{rs.completions}</Text>
                </View>
              ))}
            </View>
          )}
        </View>

        {/* Overall progress */}
        <View style={styles.chartCard}>
          <Text style={styles.chartTitle}>Overall Progress</Text>
          <View style={styles.overallRow}>
            <View style={styles.overallLeft}>
              <Text style={styles.overallValue}>{completionRate}%</Text>
              <Text style={styles.overallLabel}>Completion Rate</Text>
            </View>
            <View style={styles.overallRight}>
              <View style={styles.overallBarTrack}>
                <View
                  style={[
                    styles.overallBar,
                    {
                      width: `${completionRate}%`,
                      backgroundColor: completionRate >= 70 ? Colors.success : completionRate >= 40 ? Colors.warning : Colors.error,
                    },
                  ]}
                />
              </View>
              <Text style={styles.overallDetail}>
                {totalCompletions} of {tasks.length} tasks completed
              </Text>
            </View>
          </View>
        </View>

        {completions.length === 0 && !loading && (
          <EmptyState
            icon={<TrendingUp size={32} color={Colors.primary} strokeWidth={2} />}
            title="No data yet"
            subtitle="Complete some tasks to see your stats here."
          />
        )}

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
    paddingBottom: Spacing.lg,
  },
  headerTitle: {
    fontSize: FontSizes.xxxl,
    fontWeight: '800',
    color: Colors.text,
  },
  headerSubtitle: {
    fontSize: FontSizes.sm,
    color: Colors.textTertiary,
    marginTop: 2,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: Spacing.xl,
  },
  topStatsRow: {
    flexDirection: 'row',
    gap: Spacing.md,
    marginBottom: Spacing.md,
  },
  streakCard: {
    flex: 1,
    backgroundColor: Colors.surface,
    borderRadius: BorderRadius.xl,
    padding: Spacing.xl,
    alignItems: 'center',
    gap: Spacing.sm,
    borderWidth: 1,
    borderColor: Colors.border,
    ...Shadows.sm,
  },
  streakIcon: {
    width: 56,
    height: 56,
    borderRadius: 28,
    alignItems: 'center',
    justifyContent: 'center',
  },
  streakValue: {
    fontSize: FontSizes.xxxl,
    fontWeight: '800',
    color: Colors.text,
  },
  streakLabel: {
    fontSize: FontSizes.sm,
    color: Colors.textTertiary,
    fontWeight: '500',
  },
  statCardsRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: Spacing.md,
    marginBottom: Spacing.md,
  },
  chartCard: {
    backgroundColor: Colors.surface,
    borderRadius: BorderRadius.xl,
    padding: Spacing.xl,
    marginBottom: Spacing.md,
    borderWidth: 1,
    borderColor: Colors.border,
    ...Shadows.sm,
  },
  chartTitle: {
    fontSize: FontSizes.lg,
    fontWeight: '700',
    color: Colors.text,
    marginBottom: Spacing.lg,
  },
  barChart: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
    height: 140,
  },
  barCol: {
    alignItems: 'center',
    gap: 4,
    flex: 1,
  },
  barTrack: {
    flex: 1,
    width: BAR_WIDTH,
    justifyContent: 'flex-end',
    alignItems: 'center',
  },
  bar: {
    width: '100%',
    borderRadius: 6,
    minHeight: 4,
  },
  barLabel: {
    fontSize: FontSizes.xs,
    color: Colors.textTertiary,
    fontWeight: '600',
  },
  barLabelToday: {
    color: Colors.primary,
  },
  barCount: {
    fontSize: 10,
    color: Colors.textSecondary,
    fontWeight: '600',
  },
  barCountToday: {
    color: Colors.primary,
  },
  roomBars: {
    gap: Spacing.md,
  },
  roomBarRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
  },
  roomBarInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    width: 90,
  },
  roomBarIcon: {
    fontSize: 16,
  },
  roomBarName: {
    fontSize: FontSizes.sm,
    fontWeight: '600',
    color: Colors.text,
  },
  roomBarTrack: {
    flex: 1,
    height: 24,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: BorderRadius.md,
    overflow: 'hidden',
  },
  roomBar: {
    height: '100%',
    borderRadius: BorderRadius.md,
  },
  roomBarCount: {
    fontSize: FontSizes.sm,
    fontWeight: '700',
    color: Colors.text,
    minWidth: 24,
    textAlign: 'right',
  },
  overallRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xl,
  },
  overallLeft: {
    alignItems: 'center',
  },
  overallValue: {
    fontSize: FontSizes.huge,
    fontWeight: '800',
    color: Colors.text,
  },
  overallLabel: {
    fontSize: FontSizes.xs,
    color: Colors.textTertiary,
    fontWeight: '500',
    marginTop: 2,
  },
  overallRight: {
    flex: 1,
    gap: Spacing.sm,
  },
  overallBarTrack: {
    height: 12,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 6,
    overflow: 'hidden',
  },
  overallBar: {
    height: '100%',
    borderRadius: 6,
  },
  overallDetail: {
    fontSize: FontSizes.xs,
    color: Colors.textTertiary,
  },
  emptyText: {
    fontSize: FontSizes.sm,
    color: Colors.textTertiary,
    textAlign: 'center',
    paddingVertical: Spacing.xl,
  },
});
