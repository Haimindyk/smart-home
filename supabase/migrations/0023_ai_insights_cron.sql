-- Phase 2: a periodic sweep that asks the assistant Edge Function to look
-- for a genuinely useful observation (a chore nobody's done in a while, a
-- shopping item that keeps recurring) and, if it finds one, write it to
-- ai_suggestions as a dismissible dashboard card. Mirrors the
-- pg_cron + pg_net + Vault pattern already used for push notifications
-- (0006) and family-event reminders (0010).
--
-- Unlike the chat intent (open to anyone with the link, like the rest of
-- this app), the insights intent is gated by a shared secret — an open
-- endpoint here would let anyone spam the whole household's dashboard with
-- junk suggestion cards, which is a real annoyance vector chat isn't
-- (chat's cost/abuse surface is already covered by the ai_usage cap).

create or replace function public.verify_assistant_trigger_secret(p_secret text)
returns boolean
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'assistant_trigger_secret';
  return v_secret is not null and v_secret = p_secret;
end;
$$;

grant execute on function public.verify_assistant_trigger_secret(text) to anon, authenticated;

create or replace function public.check_ai_insights()
returns void
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'assistant_trigger_secret';
  if v_secret is null then
    return; -- not configured yet — no-op, same as notify_push()
  end if;

  perform net.http_post(
    url := 'https://ogoxwhebqxjligxeqnqd.functions.supabase.co/assistant',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := jsonb_build_object('intent', 'insights', 'locale', 'he')
  );
end;
$$;

-- A few times a day rather than continuously — a family app punishes
-- over-nagging, and this also keeps free-tier LLM usage low.
select cron.schedule('check-ai-insights', '0 6,12,18 * * *', $$select public.check_ai_insights();$$);
