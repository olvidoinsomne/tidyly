export type Priority = 'low' | 'medium' | 'high';

export interface Room {
  id: string;
  name: string;
  icon: string;
  color: string;
  sort_order: number;
  created_at: string;
}

export interface Task {
  id: string;
  room_id: string;
  title: string;
  frequency_days: number;
  priority: Priority;
  estimated_minutes: number;
  last_done_at: string | null;
  next_due_at: string;
  sort_order: number;
  created_at: string;
}

export interface Completion {
  id: string;
  task_id: string;
  room_id: string;
  completed_at: string;
  created_at: string;
}

export interface Settings {
  id: number;
  household_name: string;
  dark_mode: boolean;
  notifications_enabled: boolean;
  week_starts_monday: boolean;
  updated_at: string;
}

export interface TaskWithRoom extends Task {
  rooms: Pick<Room, 'id' | 'name' | 'icon' | 'color'>;
}

export interface RoomWithTasks extends Room {
  tasks: Task[];
  completionRate: number;
  overdueCount: number;
  dueCount: number;
}
