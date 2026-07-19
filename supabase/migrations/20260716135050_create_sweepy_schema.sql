/*
# Sweepy-style cleaning app schema (single-tenant, no auth)

1. New Tables
- `rooms` — each room in the home (Kitchen, Bathroom, etc.)
  - id (uuid, PK)
  - name (text, not null)
  - icon (text, not null) — emoji or icon key
  - color (text, not null) — hex color string
  - sort_order (int, default 0)
  - created_at (timestamptz)
- `tasks` — recurring cleaning tasks tied to a room
  - id (uuid, PK)
  - room_id (uuid, FK -> rooms.id ON DELETE CASCADE)
  - title (text, not null)
  - frequency_days (int, not null default 7) — how often the task repeats
  - priority (text, not null default 'medium') — low | medium | high
  - estimated_minutes (int, default 10)
  - last_done_at (date, nullable) — last completion date
  - next_due_at (date, not null) — next due date
  - sort_order (int, default 0)
  - created_at (timestamptz)
- `completions` — log every time a task is completed
  - id (uuid, PK)
  - task_id (uuid, FK -> tasks.id ON DELETE CASCADE)
  - room_id (uuid, FK -> rooms.id ON DELETE CASCADE)
  - completed_at (date, not null) — the date the task was done
  - created_at (timestamptz)
- `settings` — app-level preferences (single row)
  - id (int, PK, always 1)
  - household_name (text, default 'My Home')
  - dark_mode (boolean, default false)
  - notifications_enabled (boolean, default true)
  - week_starts_monday (boolean, default true)
  - updated_at (timestamptz)
2. Security
- Enable RLS on all tables.
- Single-tenant: all policies TO anon, authenticated with USING (true) / WITH CHECK (true).
3. Notes
- `next_due_at` is computed by the client on task creation and recalculated after each completion.
- `completions` table powers streaks and statistics.
- `settings` table has a single row enforced by a partial unique index on id=1.
*/

CREATE TABLE IF NOT EXISTS rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  icon text NOT NULL DEFAULT '🧹',
  color text NOT NULL DEFAULT '#3B82F6',
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_rooms" ON rooms;
CREATE POLICY "anon_select_rooms" ON rooms FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "anon_insert_rooms" ON rooms;
CREATE POLICY "anon_insert_rooms" ON rooms FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_rooms" ON rooms;
CREATE POLICY "anon_update_rooms" ON rooms FOR UPDATE
  TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_rooms" ON rooms;
CREATE POLICY "anon_delete_rooms" ON rooms FOR DELETE
  TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  title text NOT NULL,
  frequency_days int NOT NULL DEFAULT 7,
  priority text NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high')),
  estimated_minutes int NOT NULL DEFAULT 10,
  last_done_at date,
  next_due_at date NOT NULL,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tasks_next_due_at ON tasks(next_due_at);

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_tasks" ON tasks;
CREATE POLICY "anon_select_tasks" ON tasks FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "anon_insert_tasks" ON tasks;
CREATE POLICY "anon_insert_tasks" ON tasks FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_tasks" ON tasks;
CREATE POLICY "anon_update_tasks" ON tasks FOR UPDATE
  TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_tasks" ON tasks;
CREATE POLICY "anon_delete_tasks" ON tasks FOR DELETE
  TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS completions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  room_id uuid NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  completed_at date NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_completions_task_id ON completions(task_id);
CREATE INDEX IF NOT EXISTS idx_completions_completed_at ON completions(completed_at);
CREATE INDEX IF NOT EXISTS idx_completions_room_id ON completions(room_id);
CREATE INDEX IF NOT EXISTS idx_completions_task_completed_at ON completions(task_id, completed_at);

CREATE OR REPLACE FUNCTION update_room_order(room_ids uuid[])
RETURNS void
LANGUAGE sql
AS $$
  UPDATE rooms
  SET sort_order = ordered.position - 1
  FROM unnest(room_ids) WITH ORDINALITY AS ordered(id, position)
  WHERE rooms.id = ordered.id;
$$;

ALTER TABLE completions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_completions" ON completions;
CREATE POLICY "anon_select_completions" ON completions FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "anon_insert_completions" ON completions;
CREATE POLICY "anon_insert_completions" ON completions FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_completions" ON completions;
CREATE POLICY "anon_delete_completions" ON completions FOR DELETE
  TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS settings (
  id int PRIMARY KEY DEFAULT 1,
  household_name text NOT NULL DEFAULT 'My Home',
  dark_mode boolean NOT NULL DEFAULT false,
  notifications_enabled boolean NOT NULL DEFAULT true,
  week_starts_monday boolean NOT NULL DEFAULT true,
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT singleton_row CHECK (id = 1)
);

ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_settings" ON settings;
CREATE POLICY "anon_select_settings" ON settings FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "anon_insert_settings" ON settings;
CREATE POLICY "anon_insert_settings" ON settings FOR INSERT
  TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_settings" ON settings;
CREATE POLICY "anon_update_settings" ON settings FOR UPDATE
  TO anon, authenticated USING (true) WITH CHECK (true);

INSERT INTO settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- Seed default rooms
INSERT INTO rooms (name, icon, color, sort_order)
SELECT * FROM (VALUES
  ('Kitchen', '🍽️', '#F59E0B', 0),
  ('Bathroom', '🚿', '#06B6D4', 1),
  ('Living Room', '🛋️', '#8B5CF6', 2),
  ('Bedroom', '🛏️', '#EC4899', 3),
  ('Office', '💻', '#6366F1', 4)
) AS v(name, icon, color, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM rooms);

-- Seed default tasks for each room
INSERT INTO tasks (room_id, title, frequency_days, priority, estimated_minutes, next_due_at)
SELECT r.id, v.title, v.frequency_days, v.priority, v.estimated_minutes, CURRENT_DATE + (v.frequency_days / 2)
FROM rooms r
JOIN (VALUES
  ('Kitchen', 'Wipe countertops', 1, 'high', 5),
  ('Kitchen', 'Do the dishes', 1, 'high', 15),
  ('Kitchen', 'Clean stove', 3, 'medium', 10),
  ('Kitchen', 'Mop the floor', 7, 'medium', 20),
  ('Kitchen', 'Clean fridge', 14, 'low', 30),
  ('Bathroom', 'Wipe sink', 2, 'high', 5),
  ('Bathroom', 'Clean toilet', 3, 'high', 10),
  ('Bathroom', 'Clean shower', 7, 'medium', 20),
  ('Bathroom', 'Mop the floor', 7, 'medium', 15),
  ('Living Room', 'Vacuum', 3, 'medium', 15),
  ('Living Room', 'Dust surfaces', 7, 'low', 10),
  ('Living Room', 'Clean windows', 14, 'low', 15),
  ('Bedroom', 'Make the bed', 1, 'medium', 3),
  ('Bedroom', 'Change sheets', 7, 'medium', 10),
  ('Bedroom', 'Organize clothes', 14, 'low', 20),
  ('Office', 'Clear desk', 2, 'medium', 5),
  ('Office', 'Organize files', 30, 'low', 30),
  ('Office', 'Dust electronics', 7, 'low', 10)
) AS v(room_name, title, frequency_days, priority, estimated_minutes)
ON v.room_name = r.name
WHERE NOT EXISTS (SELECT 1 FROM tasks t WHERE t.room_id = r.id AND t.title = v.title);
