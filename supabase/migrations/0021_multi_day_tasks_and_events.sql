-- Allow a task's due date and a family event's date to span more than one
-- day. Both new columns are purely additive: null means "single day", same
-- as today. Reminders still fire off the existing start-date columns
-- (due_at / event_date via family_event_next_occurrence) — the range only
-- affects how these show up in the calendar view.

alter table public.tasks add column if not exists due_end_at timestamptz;
alter table public.tasks add constraint tasks_due_end_after_start
  check (due_end_at is null or due_at is null or due_end_at >= due_at);

alter table public.family_events add column if not exists end_date date;
alter table public.family_events add constraint family_events_end_after_start
  check (end_date is null or end_date >= event_date);
