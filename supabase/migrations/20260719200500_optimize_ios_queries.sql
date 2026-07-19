CREATE INDEX IF NOT EXISTS idx_tasks_next_due_at ON tasks(next_due_at);
CREATE INDEX IF NOT EXISTS idx_completions_task_completed_at
  ON completions(task_id, completed_at);

CREATE OR REPLACE FUNCTION update_room_order(room_ids uuid[])
RETURNS void
LANGUAGE sql
AS $$
  UPDATE rooms
  SET sort_order = ordered.position - 1
  FROM unnest(room_ids) WITH ORDINALITY AS ordered(id, position)
  WHERE rooms.id = ordered.id;
$$;
