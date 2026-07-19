import React, { useState, useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl, TouchableOpacity, Alert } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { Plus, ChevronRight, Check, Clock, AlertCircle } from 'lucide-react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Colors, Spacing, BorderRadius, FontSizes, Shadows } from '@/lib/theme';
import { RoomProgressCard } from '@/components/RoomProgressCard';
import { RoomEditor } from '@/components/RoomEditor';
import { TaskEditor } from '@/components/TaskEditor';
import { EmptyState } from '@/components/EmptyState';
import {
  fetchRoomsWithTasks,
  completeTask,
  todayISO,
  formatRelativeDate,
  daysUntil,
  PRIORITIES,
} from '@/lib/database';
import type { RoomWithTasks, Room, Task } from '@/lib/types';

export default function RoomsScreen() {
  const [rooms, setRooms] = useState<RoomWithTasks[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [showRoomEditor, setShowRoomEditor] = useState(false);
  const [editingRoom, setEditingRoom] = useState<Room | null>(null);
  const [selectedRoom, setSelectedRoom] = useState<RoomWithTasks | null>(null);
  const [showTaskEditor, setShowTaskEditor] = useState(false);
  const [editingTask, setEditingTask] = useState<Task | null>(null);

  const today = todayISO();

  const loadData = useCallback(async () => {
    try {
      const data = await fetchRoomsWithTasks();
      setRooms(data);
    } catch (e) {
      console.error('Failed to load rooms', e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      loadData();
    }, [loadData])
  );

  const onRefresh = () => {
    setRefreshing(true);
    loadData();
  };

  const handleCompleteTask = async (task: Task) => {
    try {
      await completeTask(task, today);
      loadData();
    } catch {
      Alert.alert('Error', 'Could not mark task as done.');
    }
  };

  const openRoom = (room: RoomWithTasks) => {
    setSelectedRoom(room);
  };

  const closeRoomDetail = () => {
    setSelectedRoom(null);
    loadData();
  };

  const openTaskEditor = (task?: Task) => {
    setEditingTask(task ?? null);
    setShowTaskEditor(true);
  };

  if (selectedRoom) {
    return (
      <SafeAreaView style={styles.container} edges={['top']}>
        <View style={styles.detailHeader}>
          <TouchableOpacity onPress={closeRoomDetail} style={styles.backBtn}>
            <ChevronRight size={22} color={Colors.text} strokeWidth={2.5} style={{ transform: [{ rotate: '180deg' }] }} />
          </TouchableOpacity>
          <View style={styles.detailHeaderInfo}>
            <Text style={styles.detailRoomIcon}>{selectedRoom.icon}</Text>
            <Text style={styles.detailRoomName}>{selectedRoom.name}</Text>
          </View>
          <TouchableOpacity
            onPress={() => {
              setEditingRoom(selectedRoom);
              setShowRoomEditor(true);
            }}
            style={styles.editBtn}
          >
            <Text style={styles.editBtnText}>Edit</Text>
          </TouchableOpacity>
        </View>

        <ScrollView
          style={styles.scrollView}
          contentContainerStyle={styles.scrollContent}
          showsVerticalScrollIndicator={false}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
        >
          {/* Room stats */}
          <View style={styles.roomStatsRow}>
            <View style={styles.roomStatCard}>
              <Text style={styles.roomStatValue}>{selectedRoom.tasks.length}</Text>
              <Text style={styles.roomStatLabel}>Total Tasks</Text>
            </View>
            <View style={styles.roomStatCard}>
              <Text style={styles.roomStatValue}>{selectedRoom.dueCount}</Text>
              <Text style={styles.roomStatLabel}>Due Now</Text>
            </View>
            <View style={styles.roomStatCard}>
              <Text style={[styles.roomStatValue, { color: Colors.error }]}>{selectedRoom.overdueCount}</Text>
              <Text style={styles.roomStatLabel}>Overdue</Text>
            </View>
          </View>

          {/* Tasks */}
          {selectedRoom.tasks.length === 0 ? (
            <EmptyState
              icon={<Plus size={32} color={Colors.primary} strokeWidth={2} />}
              title="No tasks yet"
              subtitle="Add cleaning tasks for this room."
            />
          ) : (
            <View style={styles.taskList}>
              {selectedRoom.tasks.map((task) => {
                const isOverdue = task.next_due_at < today;
                const isDueToday = task.next_due_at === today;
                const priority = PRIORITIES[task.priority];
                return (
                  <TouchableOpacity
                    key={task.id}
                    style={styles.taskRow}
                    onPress={() => openTaskEditor(task)}
                    activeOpacity={0.7}
                  >
                    <TouchableOpacity
                      style={styles.taskCheck}
                      onPress={() => handleCompleteTask(task)}
                    >
                      <View style={[styles.checkCircle, { borderColor: Colors.borderDark }]} />
                    </TouchableOpacity>
                    <View style={styles.taskContent}>
                      <Text style={styles.taskTitle}>{task.title}</Text>
                      <View style={styles.taskMeta}>
                        <View style={[styles.priorityTag, { backgroundColor: priority.bgColor }]}>
                          <View style={[styles.priorityDot, { backgroundColor: priority.color }]} />
                          <Text style={[styles.priorityText, { color: priority.color }]}>{priority.label}</Text>
                        </View>
                        <View style={styles.timeTag}>
                          <Clock size={12} color={Colors.textTertiary} strokeWidth={2} />
                          <Text style={styles.timeText}>{task.estimated_minutes}m</Text>
                        </View>
                        <Text style={styles.freqText}>Every {task.frequency_days}d</Text>
                      </View>
                    </View>
                    <View style={[styles.dueBadge, isOverdue && styles.overdueBadge, isDueToday && styles.dueTodayBadge]}>
                      {isOverdue && <AlertCircle size={11} color={Colors.error} strokeWidth={2.5} />}
                      <Text style={[styles.dueText, isOverdue && styles.overdueText, isDueToday && styles.dueTodayText]}>
                        {formatRelativeDate(task.next_due_at)}
                      </Text>
                    </View>
                  </TouchableOpacity>
                );
              })}
            </View>
          )}

          <TouchableOpacity
            style={styles.addTaskBtn}
            onPress={() => openTaskEditor()}
          >
            <Plus size={20} color={Colors.primary} strokeWidth={2.5} />
            <Text style={styles.addTaskText}>Add Task to {selectedRoom.name}</Text>
          </TouchableOpacity>

          <View style={{ height: 40 }} />
        </ScrollView>

        <TaskEditor
          visible={showTaskEditor}
          onClose={() => setShowTaskEditor(false)}
          onSaved={loadData}
          room={selectedRoom}
          task={editingTask}
        />

        <RoomEditor
          visible={showRoomEditor}
          onClose={() => {
            setShowRoomEditor(false);
            setEditingRoom(null);
          }}
          onSaved={loadData}
          room={editingRoom}
        />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Rooms</Text>
        <Text style={styles.headerSubtitle}>{rooms.length} rooms in your home</Text>
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        {rooms.length === 0 && !loading ? (
          <EmptyState
            icon={<Plus size={32} color={Colors.primary} strokeWidth={2} />}
            title="No rooms yet"
            subtitle="Add your first room to start organizing cleaning tasks."
          />
        ) : (
          <View style={styles.roomList}>
            {rooms.map((room) => (
              <TouchableOpacity key={room.id} onPress={() => openRoom(room)} activeOpacity={0.7}>
                <RoomProgressCard
                  name={room.name}
                  icon={room.icon}
                  color={room.color}
                  completionRate={room.completionRate}
                  dueCount={room.dueCount}
                  overdueCount={room.overdueCount}
                  taskCount={room.tasks.length}
                />
              </TouchableOpacity>
            ))}
          </View>
        )}

        <TouchableOpacity
          style={styles.addRoomBtn}
          onPress={() => {
            setEditingRoom(null);
            setShowRoomEditor(true);
          }}
        >
          <Plus size={20} color={Colors.primary} strokeWidth={2.5} />
          <Text style={styles.addRoomText}>Add New Room</Text>
        </TouchableOpacity>

        <View style={{ height: 100 }} />
      </ScrollView>

      <RoomEditor
        visible={showRoomEditor}
        onClose={() => setShowRoomEditor(false)}
        onSaved={loadData}
        room={editingRoom}
      />
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
  roomList: {
    gap: Spacing.md,
  },
  addRoomBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: Spacing.md,
    borderRadius: BorderRadius.lg,
    borderWidth: 2,
    borderColor: Colors.border,
    borderStyle: 'dashed',
    marginTop: Spacing.lg,
  },
  addRoomText: {
    fontSize: FontSizes.md,
    fontWeight: '600',
    color: Colors.primary,
  },
  // Detail view
  detailHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: Spacing.lg,
    paddingTop: Spacing.lg,
    paddingBottom: Spacing.md,
    gap: Spacing.md,
  },
  backBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: Colors.surfaceAlt,
    alignItems: 'center',
    justifyContent: 'center',
  },
  detailHeaderInfo: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  detailRoomIcon: {
    fontSize: 28,
  },
  detailRoomName: {
    fontSize: FontSizes.xl,
    fontWeight: '700',
    color: Colors.text,
  },
  editBtn: {
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.sm,
    borderRadius: BorderRadius.md,
    backgroundColor: Colors.surfaceAlt,
  },
  editBtnText: {
    fontSize: FontSizes.sm,
    fontWeight: '600',
    color: Colors.primary,
  },
  roomStatsRow: {
    flexDirection: 'row',
    gap: Spacing.md,
    marginBottom: Spacing.xl,
    paddingHorizontal: Spacing.xl,
  },
  roomStatCard: {
    flex: 1,
    backgroundColor: Colors.surface,
    borderRadius: BorderRadius.lg,
    padding: Spacing.md,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: Colors.border,
    ...Shadows.sm,
  },
  roomStatValue: {
    fontSize: FontSizes.xxxl,
    fontWeight: '800',
    color: Colors.text,
  },
  roomStatLabel: {
    fontSize: FontSizes.xs,
    color: Colors.textTertiary,
    fontWeight: '500',
    marginTop: 2,
  },
  taskList: {
    gap: Spacing.md,
    paddingHorizontal: Spacing.xl,
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
  taskCheck: {
    width: 28,
    height: 28,
  },
  checkCircle: {
    width: 28,
    height: 28,
    borderRadius: 14,
    borderWidth: 2,
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
  taskMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
    flexWrap: 'wrap',
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
  freqText: {
    fontSize: FontSizes.xs,
    color: Colors.textTertiary,
    fontWeight: '500',
  },
  dueBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
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
  addTaskBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: Spacing.md,
    borderRadius: BorderRadius.lg,
    borderWidth: 2,
    borderColor: Colors.border,
    borderStyle: 'dashed',
    marginHorizontal: Spacing.xl,
    marginTop: Spacing.lg,
  },
  addTaskText: {
    fontSize: FontSizes.md,
    fontWeight: '600',
    color: Colors.primary,
  },
});
