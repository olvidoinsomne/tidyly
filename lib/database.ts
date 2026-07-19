import { supabase } from './supabase';
import type { Room, Task, Completion, Settings, RoomWithTasks, TaskWithRoom, Priority } from './types';

export const PRIORITIES: Record<Priority, { label: string; color: string; bgColor: string }> = {
  high: { label: 'High', color: '#EF4444', bgColor: 'rgba(239, 68, 68, 0.12)' },
  medium: { label: 'Medium', color: '#F59E0B', bgColor: 'rgba(245, 158, 11, 0.12)' },
  low: { label: 'Low', color: '#10B981', bgColor: 'rgba(16, 185, 129, 0.12)' },
};

export const ROOM_ICONS = [
  '🍽️', '🚿', '🛋️', '🛏️', '💻', '🚗', '🌿', '🧺', '🚪', '🪟',
  '🛁', '🧽', '📦', '🐶', '👕', '📚', '🎮', '🍳', '🪴', '🔧',
];

export const ROOM_COLORS = [
  '#F59E0B', '#06B6D4', '#8B5CF6', '#EC4899', '#6366F1',
  '#10B981', '#EF4444', '#14B8A6', '#F97316', '#3B82F6',
];

export function todayISO(): string {
  return new Date().toISOString().split('T')[0];
}

export function addDays(dateStr: string, days: number): string {
  const d = new Date(dateStr + 'T00:00:00');
  d.setDate(d.getDate() + days);
  return d.toISOString().split('T')[0];
}

export function daysUntil(dateStr: string): number {
  const today = new Date(todayISO() + 'T00:00:00');
  const target = new Date(dateStr + 'T00:00:00');
  return Math.round((target.getTime() - today.getTime()) / 86400000);
}

export function formatRelativeDate(dateStr: string): string {
  const diff = daysUntil(dateStr);
  if (diff < 0) return `${Math.abs(diff)}d overdue`;
  if (diff === 0) return 'Today';
  if (diff === 1) return 'Tomorrow';
  if (diff <= 7) return `In ${diff} days`;
  const d = new Date(dateStr + 'T00:00:00');
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

export function formatFullDate(dateStr: string): string {
  const d = new Date(dateStr + 'T00:00:00');
  return d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
}

export function getWeekStart(date: Date = new Date(), weekStartsMonday = true): string {
  const d = new Date(date);
  const day = d.getDay();
  const offset = weekStartsMonday ? (day === 0 ? 6 : day - 1) : day;
  d.setDate(d.getDate() - offset);
  return d.toISOString().split('T')[0];
}

export function getWeekDates(weekStart: string): string[] {
  const dates: string[] = [];
  for (let i = 0; i < 7; i++) {
    dates.push(addDays(weekStart, i));
  }
  return dates;
}

// ---- Rooms ----

export async function fetchRooms(): Promise<Room[]> {
  const { data, error } = await supabase
    .from('rooms')
    .select('*')
    .order('sort_order', { ascending: true });
  if (error) throw error;
  return data || [];
}

export async function fetchRoomsWithTasks(): Promise<RoomWithTasks[]> {
  const [rooms, tasks] = await Promise.all([fetchRooms(), fetchAllTasks()]);
  const today = todayISO();

  return rooms.map((room, idx) => {
    const roomTasks = tasks.filter((t) => t.room_id === room.id);
    const overdueCount = roomTasks.filter((t) => t.next_due_at < today).length;
    const dueCount = roomTasks.filter((t) => t.next_due_at <= today).length;
    const completedCount = roomTasks.filter(
      (t) => t.last_done_at !== null && daysUntil(addDays(t.last_done_at!, t.frequency_days)) >= 0
    ).length;
    const completionRate = roomTasks.length > 0
      ? Math.round((completedCount / roomTasks.length) * 100)
      : 0;
    return {
      ...room,
      tasks: roomTasks.sort((a, b) => a.next_due_at.localeCompare(b.next_due_at)),
      completionRate,
      overdueCount,
      dueCount,
    };
  });
}

export async function createRoom(name: string, icon: string, color: string): Promise<Room> {
  const { data: maxOrder } = await supabase
    .from('rooms')
    .select('sort_order')
    .order('sort_order', { ascending: false })
    .limit(1)
    .maybeSingle();

  const sortOrder = maxOrder ? maxOrder.sort_order + 1 : 0;
  const { data, error } = await supabase
    .from('rooms')
    .insert({ name, icon, color, sort_order: sortOrder })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateRoom(id: string, updates: Partial<Pick<Room, 'name' | 'icon' | 'color'>>): Promise<void> {
  const { error } = await supabase.from('rooms').update(updates).eq('id', id);
  if (error) throw error;
}

export async function deleteRoom(id: string): Promise<void> {
  const { error } = await supabase.from('rooms').delete().eq('id', id);
  if (error) throw error;
}

// ---- Tasks ----

export async function fetchAllTasks(): Promise<Task[]> {
  const { data, error } = await supabase
    .from('tasks')
    .select('*')
    .order('sort_order', { ascending: true });
  if (error) throw error;
  return data || [];
}

export async function fetchTasksForRoom(roomId: string): Promise<Task[]> {
  const { data, error } = await supabase
    .from('tasks')
    .select('*')
    .eq('room_id', roomId)
    .order('next_due_at', { ascending: true });
  if (error) throw error;
  return data || [];
}

export async function fetchTasksForDate(dateStr: string): Promise<TaskWithRoom[]> {
  const { data, error } = await supabase
    .from('tasks')
    .select('*, rooms(id, name, icon, color)')
    .lte('next_due_at', dateStr)
    .order('priority', { ascending: false })
    .order('next_due_at', { ascending: true });
  if (error) throw error;
  return (data || []) as TaskWithRoom[];
}

export async function fetchTasksForWeek(weekStart: string): Promise<TaskWithRoom[]> {
  const weekEnd = addDays(weekStart, 6);
  const { data, error } = await supabase
    .from('tasks')
    .select('*, rooms(id, name, icon, color)')
    .lte('next_due_at', weekEnd)
    .order('next_due_at', { ascending: true });
  if (error) throw error;
  return (data || []) as TaskWithRoom[];
}

export async function createTask(input: {
  room_id: string;
  title: string;
  frequency_days: number;
  priority: Priority;
  estimated_minutes: number;
}): Promise<Task> {
  const nextDue = addDays(todayISO(), Math.floor(input.frequency_days / 2));
  const { data: maxOrder } = await supabase
    .from('tasks')
    .select('sort_order')
    .eq('room_id', input.room_id)
    .order('sort_order', { ascending: false })
    .limit(1)
    .maybeSingle();

  const sortOrder = maxOrder ? maxOrder.sort_order + 1 : 0;
  const { data, error } = await supabase
    .from('tasks')
    .insert({ ...input, next_due_at: nextDue, sort_order: sortOrder })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateTask(id: string, updates: Partial<Task>): Promise<void> {
  const { error } = await supabase.from('tasks').update(updates).eq('id', id);
  if (error) throw error;
}

export async function deleteTask(id: string): Promise<void> {
  const { error } = await supabase.from('tasks').delete().eq('id', id);
  if (error) throw error;
}

export async function completeTask(task: Task, completedDate: string = todayISO()): Promise<void> {
  const nextDue = addDays(completedDate, task.frequency_days);
  await supabase
    .from('tasks')
    .update({ last_done_at: completedDate, next_due_at: nextDue })
    .eq('id', task.id);
  await supabase.from('completions').insert({
    task_id: task.id,
    room_id: task.room_id,
    completed_at: completedDate,
  });
}

export async function undoCompletion(task: Task, completionId: string): Promise<void> {
  await supabase.from('completions').delete().eq('id', completionId);
  const { data: lastCompletion } = await supabase
    .from('completions')
    .select('completed_at')
    .eq('task_id', task.id)
    .order('completed_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  const lastDone = lastCompletion ? lastCompletion.completed_at : null;
  const nextDue = lastDone ? addDays(lastDone, task.frequency_days) : addDays(todayISO(), Math.floor(task.frequency_days / 2));
  await supabase
    .from('tasks')
    .update({ last_done_at: lastDone, next_due_at: nextDue })
    .eq('id', task.id);
}

// ---- Completions / Stats ----

export async function fetchCompletionsInRange(startDate: string, endDate: string): Promise<Completion[]> {
  const { data, error } = await supabase
    .from('completions')
    .select('*')
    .gte('completed_at', startDate)
    .lte('completed_at', endDate)
    .order('completed_at', { ascending: true });
  if (error) throw error;
  return data || [];
}

export async function fetchRecentCompletions(limit = 10): Promise<Completion[]> {
  const { data, error } = await supabase
    .from('completions')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data || [];
}

export async function fetchCompletionByTaskAndDate(taskId: string, dateStr: string): Promise<Completion | null> {
  const { data, error } = await supabase
    .from('completions')
    .select('*')
    .eq('task_id', taskId)
    .eq('completed_at', dateStr)
    .maybeSingle();
  if (error) throw error;
  return data;
}

// ---- Settings ----

export async function fetchSettings(): Promise<Settings> {
  const { data, error } = await supabase
    .from('settings')
    .select('*')
    .eq('id', 1)
    .maybeSingle();
  if (error) throw error;
  if (!data) {
    const { data: created, error: insertError } = await supabase
      .from('settings')
      .insert({ id: 1 })
      .select()
      .single();
    if (insertError) throw insertError;
    return created;
  }
  return data;
}

export async function updateSettings(updates: Partial<Omit<Settings, 'id' | 'updated_at'>>): Promise<void> {
  const { error } = await supabase
    .from('settings')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', 1);
  if (error) throw error;
}
