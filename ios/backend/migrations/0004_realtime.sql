-- Publish row-level changes for every collaborative table so the app can
-- subscribe per-area over Supabase Realtime (postgres_changes), same
-- approach as the website.
alter publication supabase_realtime add table public.areas;
alter publication supabase_realtime add table public.area_members;
alter publication supabase_realtime add table public.sections;
alter publication supabase_realtime add table public.tasks;
alter publication supabase_realtime add table public.chores;
alter publication supabase_realtime add table public.chore_completions;
alter publication supabase_realtime add table public.calendar_events;
alter publication supabase_realtime add table public.activity_log;
