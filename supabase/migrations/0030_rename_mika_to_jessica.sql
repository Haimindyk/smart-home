-- The household renamed the assistant from מיקה (Mika) to ג'סיקה (Jessica).
-- Same feminine persona/grammar (see JESSICA_PERSONA in the Edge Function
-- and migration 0028) — only the display name changes.
update public.members set display_name = 'ג''סיקה' where email = 'assistant@kh.family';
