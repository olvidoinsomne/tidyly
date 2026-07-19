import React, { useState, useEffect } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, ScrollView, Alert } from 'react-native';
import { Trash2 } from 'lucide-react-native';
import { Sheet } from './Sheet';
import { Colors, Spacing, BorderRadius, FontSizes } from '@/lib/theme';
import { ROOM_ICONS, ROOM_COLORS, createRoom, updateRoom, deleteRoom } from '@/lib/database';
import type { Room } from '@/lib/types';

export function RoomEditor({
  visible,
  onClose,
  onSaved,
  room,
}: {
  visible: boolean;
  onClose: () => void;
  onSaved: () => void;
  room?: Room | null;
}) {
  const [name, setName] = useState('');
  const [icon, setIcon] = useState(ROOM_ICONS[0]);
  const [color, setColor] = useState(ROOM_COLORS[0]);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (visible) {
      setName(room?.name ?? '');
      setIcon(room?.icon ?? ROOM_ICONS[0]);
      setColor(room?.color ?? ROOM_COLORS[0]);
    }
  }, [visible, room]);

  const handleSave = async () => {
    if (!name.trim()) return;
    setSaving(true);
    try {
      if (room) {
        await updateRoom(room.id, { name: name.trim(), icon, color });
      } else {
        await createRoom(name.trim(), icon, color);
      }
      onSaved();
      onClose();
    } catch (e) {
      Alert.alert('Error', 'Could not save room.');
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = () => {
    if (!room) return;
    Alert.alert(
      'Delete Room',
      `Delete "${room.name}" and all its tasks? This cannot be undone.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            try {
              await deleteRoom(room.id);
              onSaved();
              onClose();
            } catch {
              Alert.alert('Error', 'Could not delete room.');
            }
          },
        },
      ]
    );
  };

  return (
    <Sheet visible={visible} onClose={onClose} title={room ? 'Edit Room' : 'New Room'}>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 20 }}>
        <Text style={styles.label}>Room Name</Text>
        <TextInput
          style={styles.input}
          value={name}
          onChangeText={setName}
          placeholder="e.g. Garage"
          placeholderTextColor={Colors.textTertiary}
          autoFocus={!room}
        />

        <Text style={styles.label}>Icon</Text>
        <View style={styles.iconGrid}>
          {ROOM_ICONS.map((ic) => (
            <TouchableOpacity
              key={ic}
              style={[styles.iconCell, icon === ic && styles.iconCellSelected]}
              onPress={() => setIcon(ic)}
            >
              <Text style={styles.iconEmoji}>{ic}</Text>
            </TouchableOpacity>
          ))}
        </View>

        <Text style={styles.label}>Color</Text>
        <View style={styles.colorRow}>
          {ROOM_COLORS.map((c) => (
            <TouchableOpacity
              key={c}
              style={[styles.colorDot, { backgroundColor: c }, color === c && styles.colorDotSelected]}
              onPress={() => setColor(c)}
            />
          ))}
        </View>

        <View style={styles.actions}>
          {room && (
            <TouchableOpacity style={styles.deleteBtn} onPress={handleDelete}>
              <Trash2 size={20} color={Colors.error} strokeWidth={2} />
              <Text style={styles.deleteText}>Delete</Text>
            </TouchableOpacity>
          )}
          <TouchableOpacity
            style={[styles.saveBtn, !name.trim() && styles.saveBtnDisabled, { flex: room ? 1 : 1 }]}
            onPress={handleSave}
            disabled={!name.trim() || saving}
          >
            <Text style={styles.saveText}>{saving ? 'Saving...' : room ? 'Save Changes' : 'Add Room'}</Text>
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
  iconGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: Spacing.sm,
  },
  iconCell: {
    width: 48,
    height: 48,
    borderRadius: BorderRadius.md,
    backgroundColor: Colors.surfaceAlt,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  iconCellSelected: {
    borderColor: Colors.primary,
    backgroundColor: Colors.primaryLight,
  },
  iconEmoji: {
    fontSize: 24,
  },
  colorRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: Spacing.md,
  },
  colorDot: {
    width: 40,
    height: 40,
    borderRadius: 20,
    borderWidth: 3,
    borderColor: 'transparent',
  },
  colorDotSelected: {
    borderColor: Colors.text,
  },
  actions: {
    flexDirection: 'row',
    gap: Spacing.md,
    marginTop: Spacing.xxl,
    paddingBottom: Spacing.xl,
  },
  deleteBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingVertical: Spacing.md,
    borderRadius: BorderRadius.md,
    backgroundColor: 'rgba(239, 68, 68, 0.08)',
    flex: 1,
  },
  deleteText: {
    color: Colors.error,
    fontSize: FontSizes.md,
    fontWeight: '600',
  },
  saveBtn: {
    backgroundColor: Colors.primary,
    paddingVertical: Spacing.md,
    borderRadius: BorderRadius.md,
    alignItems: 'center',
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
