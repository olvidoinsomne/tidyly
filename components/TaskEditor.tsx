import React, { useState, useEffect } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, ScrollView, Alert } from 'react-native';
import { Trash2, Minus, Plus } from 'lucide-react-native';
import { Sheet } from './Sheet';
import { Colors, Spacing, BorderRadius, FontSizes } from '@/lib/theme';
import { createTask, updateTask, deleteTask, PRIORITIES } from '@/lib/database';
import type { Task, Room, Priority } from '@/lib/types';

const FREQUENCIES = [
  { label: 'Every day', value: 1 },
  { label: 'Every 2 days', value: 2 },
  { label: 'Every 3 days', value: 3 },
  { label: 'Twice a week', value: 4 },
  { label: 'Weekly', value: 7 },
  { label: 'Biweekly', value: 14 },
  { label: 'Monthly', value: 30 },
];

export function TaskEditor({
  visible,
  onClose,
  onSaved,
  room,
  task,
  rooms,
}: {
  visible: boolean;
  onClose: () => void;
  onSaved: () => void;
  room: Room;
  task?: Task | null;
  rooms?: Room[];
}) {
  const [title, setTitle] = useState('');
  const [frequency, setFrequency] = useState(7);
  const [priority, setPriority] = useState<Priority>('medium');
  const [minutes, setMinutes] = useState(10);
  const [selectedRoomId, setSelectedRoomId] = useState(room.id);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (visible) {
      setTitle(task?.title ?? '');
      setFrequency(task?.frequency_days ?? 7);
      setPriority(task?.priority ?? 'medium');
      setMinutes(task?.estimated_minutes ?? 10);
      setSelectedRoomId(task?.room_id ?? room.id);
    }
  }, [visible, task, room]);

  const handleSave = async () => {
    if (!title.trim()) return;
    setSaving(true);
    try {
      if (task) {
        await updateTask(task.id, {
          title: title.trim(),
          frequency_days: frequency,
          priority,
          estimated_minutes: minutes,
          room_id: selectedRoomId,
        });
      } else {
        await createTask({
          room_id: selectedRoomId,
          title: title.trim(),
          frequency_days: frequency,
          priority,
          estimated_minutes: minutes,
        });
      }
      onSaved();
      onClose();
    } catch (e) {
      Alert.alert('Error', 'Could not save task.');
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = () => {
    if (!task) return;
    Alert.alert('Delete Task', `Delete "${task.title}"?`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          try {
            await deleteTask(task.id);
            onSaved();
            onClose();
          } catch {
            Alert.alert('Error', 'Could not delete task.');
          }
        },
      },
    ]);
  };

  return (
    <Sheet visible={visible} onClose={onClose} title={task ? 'Edit Task' : 'New Task'}>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 20 }}>
        <Text style={styles.label}>Task Name</Text>
        <TextInput
          style={styles.input}
          value={title}
          onChangeText={setTitle}
          placeholder="e.g. Vacuum the carpet"
          placeholderTextColor={Colors.textTertiary}
          autoFocus={!task}
        />

        {rooms && rooms.length > 0 && (
          <>
            <Text style={styles.label}>Room</Text>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: Spacing.sm }}>
              {rooms.map((r) => (
                <TouchableOpacity
                  key={r.id}
                  style={[
                    styles.roomChip,
                    selectedRoomId === r.id && { backgroundColor: r.color, borderColor: r.color },
                  ]}
                  onPress={() => setSelectedRoomId(r.id)}
                >
                  <Text style={styles.roomChipIcon}>{r.icon}</Text>
                  <Text
                    style={[
                      styles.roomChipText,
                      selectedRoomId === r.id && { color: Colors.textInverse },
                    ]}
                  >
                    {r.name}
                  </Text>
                </TouchableOpacity>
              ))}
            </ScrollView>
          </>
        )}

        <Text style={styles.label}>Frequency</Text>
        <View style={styles.chipRow}>
          {FREQUENCIES.map((f) => (
            <TouchableOpacity
              key={f.value}
              style={[styles.chip, frequency === f.value && styles.chipSelected]}
              onPress={() => setFrequency(f.value)}
            >
              <Text style={[styles.chipText, frequency === f.value && styles.chipTextSelected]}>
                {f.label}
              </Text>
            </TouchableOpacity>
          ))}
        </View>

        <Text style={styles.label}>Priority</Text>
        <View style={styles.priorityRow}>
          {(Object.keys(PRIORITIES) as Priority[]).map((p) => (
            <TouchableOpacity
              key={p}
              style={[
                styles.chip,
                priority === p && { backgroundColor: PRIORITIES[p].bgColor, borderColor: PRIORITIES[p].color },
              ]}
              onPress={() => setPriority(p)}
            >
              <View style={[styles.priorityDot, { backgroundColor: PRIORITIES[p].color }]} />
              <Text style={[styles.chipText, priority === p && { color: PRIORITIES[p].color }]}>
                {PRIORITIES[p].label}
              </Text>
            </TouchableOpacity>
          ))}
        </View>

        <Text style={styles.label}>Estimated Time</Text>
        <View style={styles.stepperRow}>
          <TouchableOpacity
            style={styles.stepperBtn}
            onPress={() => setMinutes((m) => Math.max(1, m - 5))}
          >
            <Minus size={20} color={Colors.textSecondary} strokeWidth={2.5} />
          </TouchableOpacity>
          <Text style={styles.stepperValue}>{minutes} min</Text>
          <TouchableOpacity
            style={styles.stepperBtn}
            onPress={() => setMinutes((m) => Math.min(240, m + 5))}
          >
            <Plus size={20} color={Colors.textSecondary} strokeWidth={2.5} />
          </TouchableOpacity>
        </View>

        <View style={styles.actions}>
          {task && (
            <TouchableOpacity style={styles.deleteBtn} onPress={handleDelete}>
              <Trash2 size={20} color={Colors.error} strokeWidth={2} />
            </TouchableOpacity>
          )}
          <TouchableOpacity
            style={[styles.saveBtn, !title.trim() && styles.saveBtnDisabled]}
            onPress={handleSave}
            disabled={!title.trim() || saving}
          >
            <Text style={styles.saveText}>{saving ? 'Saving...' : task ? 'Save Changes' : 'Add Task'}</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </Sheet>
  );
}

const styles = StyleSheet.create({
  label: {
    fontSize: FontSizes.sm,
    fontWeight: '600',
    color: Colors.textSecondary,
    marginBottom: Spacing.sm,
    marginTop: Spacing.md,
  },
  input: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: BorderRadius.md,
    paddingHorizontal: Spacing.lg,
    paddingVertical: Spacing.md,
    fontSize: FontSizes.md,
    color: Colors.text,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  roomChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: BorderRadius.pill,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  roomChipIcon: {
    fontSize: 16,
  },
  roomChipText: {
    fontSize: FontSizes.sm,
    fontWeight: '600',
    color: Colors.textSecondary,
  },
  chipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: Spacing.sm,
  },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: BorderRadius.pill,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 2,
    borderColor: 'transparent',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  chipSelected: {
    backgroundColor: Colors.primary,
    borderColor: Colors.primary,
  },
  chipText: {
    fontSize: FontSizes.sm,
    fontWeight: '600',
    color: Colors.textSecondary,
  },
  chipTextSelected: {
    color: Colors.textInverse,
  },
  priorityRow: {
    flexDirection: 'row',
    gap: Spacing.sm,
  flexWrap: 'wrap',
  },
  priorityDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  stepperRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.xl,
  },
  stepperBtn: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: Colors.surfaceAlt,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: Colors.border,
  },
  stepperValue: {
    fontSize: FontSizes.xl,
    fontWeight: '700',
    color: Colors.text,
    minWidth: 80,
    textAlign: 'center',
  },
  actions: {
    flexDirection: 'row',
    gap: Spacing.md,
    marginTop: Spacing.xxl,
    paddingBottom: Spacing.xl,
  },
  deleteBtn: {
    width: 52,
    height: 52,
    borderRadius: BorderRadius.md,
    backgroundColor: 'rgba(239, 68, 68, 0.08)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  saveBtn: {
    backgroundColor: Colors.primary,
    paddingVertical: Spacing.md,
    borderRadius: BorderRadius.md,
    alignItems: 'center',
    flex: 1,
  },
  saveBtnDisabled: {
    opacity: 0.5,
  },
  saveText: {
    color: Colors.textInverse,
    fontSize: FontSizes.md,
    fontWeight: '700',
  },
});
