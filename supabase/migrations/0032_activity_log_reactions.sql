-- Lightweight reactions on activity_log entries (broadcasts, chore
-- completions, etc.) — a quick way to say "seen this" / "👍" without opening
-- a whole comment thread. Deliberately its own table rather than a column on
-- activity_log so multiple members can react to the same entry independently.
create table public.activity_log_reactions (
  id               uuid primary key default gen_random_uuid(),
  activity_log_id  uuid not null references public.activity_log(id) on delete cascade,
  member_id        uuid not null references public.members(id) on delete cascade,
  emoji            text not null,
  created_at       timestamptz not null default now(),
  unique (activity_log_id, member_id, emoji)
);

create index activity_log_reactions_entry_idx on public.activity_log_reactions (activity_log_id);

alter table public.activity_log_reactions enable row level security;

create policy "members full access to activity_log_reactions" on public.activity_log_reactions
  for all using (public.is_member()) with check (public.is_member());

alter publication supabase_realtime add table public.activity_log_reactions;
