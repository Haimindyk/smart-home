-- AI assistant: schema for both the conversational assistant (Phase 1) and
-- the periodic proactive-insights sweep (Phase 2). The assistant itself
-- lives entirely in a new Edge Function (supabase/functions/assistant) that
-- calls a free-tier LLM (Gemini) server-side — this migration only adds the
-- attribution identity, a usage cap so a public unauthenticated endpoint
-- can't run away with API calls, and the suggestions inbox for Phase 2.

-- ---------------------------------------------------------------------------
-- A dedicated member row for the assistant's own actions, so History reads
-- honestly ("🤖 העוזר added milk") instead of misattributing AI suggestions
-- to whichever human happened to tap "confirm". No PIN — it's never an
-- identity a person picks at the login screen (see identity-gate.tsx, which
-- only matches on `pin`).
-- ---------------------------------------------------------------------------
insert into public.members (email, display_name, avatar_emoji, color)
values ('assistant@kh.family', 'העוזר', '🤖', '#64748b')
on conflict (email) do nothing;

-- ---------------------------------------------------------------------------
-- ai_usage: one row per calendar day, incremented by the Edge Function
-- before it calls the LLM — the request is rejected once the free daily cap
-- is hit, since this endpoint has no auth and anyone with the link could
-- otherwise call it in a loop.
-- ---------------------------------------------------------------------------
create table public.ai_usage (
  day    date primary key default current_date,
  calls  int not null default 0
);

alter table public.ai_usage enable row level security;

create policy "members full access to ai_usage" on public.ai_usage
  for all using (public.is_member()) with check (public.is_member());

-- Atomically bumps today's call count and returns the new total, so the
-- Edge Function can check-then-act without a race between concurrent
-- requests. security definer + a fixed search_path since it's callable by
-- anon (see grant below).
create or replace function public.increment_ai_usage()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_calls int;
begin
  insert into public.ai_usage (day, calls) values (current_date, 1)
  on conflict (day) do update set calls = public.ai_usage.calls + 1
  returning calls into v_calls;
  return v_calls;
end;
$$;

grant execute on function public.increment_ai_usage() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- ai_suggestions: Phase 2's proactive "נראה שאף אחד לא קנה חלב..." cards,
-- written by the periodic insights sweep and shown as dismissible cards on
-- the dashboard until applied or dismissed.
-- ---------------------------------------------------------------------------
create table public.ai_suggestions (
  id          uuid primary key default gen_random_uuid(),
  summary     text not null,
  emoji       text,
  -- The exact same shape as a chat proposedAction — see
  -- src/lib/assistant/apply-actions.ts, the single place either path's
  -- actions get applied.
  action      jsonb not null,
  status      text not null default 'open' check (status in ('open', 'applied', 'dismissed')),
  created_at  timestamptz not null default now()
);

create index ai_suggestions_status_idx on public.ai_suggestions (status, created_at desc);

alter table public.ai_suggestions enable row level security;

create policy "members full access to ai_suggestions" on public.ai_suggestions
  for all using (public.is_member()) with check (public.is_member());

alter publication supabase_realtime add table public.ai_suggestions;
