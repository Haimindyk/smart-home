-- Seed: import the real K&H shared note as structured data.
-- Idempotent: only runs the bulk import if `sections` is still empty, so
-- re-running migrations against an already-seeded project is a no-op.

-- Neutral defaults on purpose: don't assume anyone's gender from their name.
-- Each person customizes their own avatar/color/name from the app (Header ->
-- profile menu -> "Edit profile").
insert into public.members (email, display_name, avatar_emoji, color) values
  ('haim_indyk@icloud.com', 'חיים', '🙂', '#3b82f6'),
  ('Koren8761@gmail.com',   'קורן', '🙂', '#10b981')
on conflict (email) do nothing;

do $$
declare
  v_haim uuid;
  v_koren uuid;

  sec_tasks       uuid := '11111111-1111-1111-1111-100000000001';
  sec_louis       uuid := '11111111-1111-1111-1111-100000000002';
  sec_pharm       uuid := '11111111-1111-1111-1111-100000000003';
  sec_ali         uuid := '11111111-1111-1111-1111-100000000004';
  sec_market      uuid := '11111111-1111-1111-1111-100000000005';
  sec_cooking     uuid := '11111111-1111-1111-1111-100000000006';
  sec_chores      uuid := '11111111-1111-1111-1111-100000000007';
  sec_love        uuid := '11111111-1111-1111-1111-100000000008';

  task_september  uuid := '22222222-2222-2222-2222-200000000001';
begin
  if exists (select 1 from public.sections) then
    return;
  end if;

  select id into v_haim  from public.members where email = 'haim_indyk@icloud.com';
  select id into v_koren from public.members where email = 'Koren8761@gmail.com';

  -- ---------------------------------------------------------------------
  -- Sections
  -- ---------------------------------------------------------------------
  insert into public.sections (id, name, emoji, kind, position) values
    (sec_tasks,   'משימות',        '💯', 'tasks',    'a0'),
    (sec_louis,   'משימות עם ולואי','🐶', 'tasks',    'a1'),
    (sec_pharm,   'סופר פארם',      '🏥', 'shopping', 'a2'),
    (sec_ali,     'AliExpress',    '📦', 'shopping', 'a3'),
    (sec_market,  'קניות בסופר',    '🛒', 'shopping', 'a4'),
    (sec_cooking, 'להכין בבית',     '🍳', 'tasks',    'a5'),
    (sec_chores,  'מטלות בית',      '🏠', 'chores',   'a6'),
    (sec_love,    'K&H',           '💙', 'tasks',    'a7');

  update public.sections set description = 'לאסוף מהארמון בגבעתיים ⛰️🦋 — קוד כניסה: 636522 🤪'
    where id = sec_pharm;
  update public.sections set description = 'ולואי 🐾 — לפני שנגמר לואי לספר לסבא'
    where id = sec_louis;

  -- ---------------------------------------------------------------------
  -- משימות (K&H tasks)
  -- ---------------------------------------------------------------------
  insert into public.tasks (section_id, position, title, assignee_kind, assignee_member_id) values
    (sec_tasks, 'a0', 'הליך פונדקאות', 'anyone', null);

  insert into public.tasks (section_id, position, title, due_at, emoji) values
    (sec_tasks, 'a1', 'תאילנד 25/1-16/2', '2027-01-25', '✈️');
  update public.tasks set notes = 'תאילנד ✈️🌴🍹 25/1/27–16/2/27' where section_id = sec_tasks and position = 'a1';

  insert into public.tasks (section_id, position, title, notes) values
    (sec_tasks, 'a2', 'בדיקת זרע לקבוע תור', 'https://m.Macb.li/30e07r7lomosozpxr');

  insert into public.tasks (section_id, position, title, notes, recurrence) values
    (sec_tasks, 'a3', 'לנצל הטבות סוף חודש',
     'שלך, מפעל הפיס, סיבוס, תן ביס', '{"freq":"monthly"}'::jsonb);

  insert into public.tasks (section_id, position, title, assignee_kind, assignee_member_id) values
    (sec_tasks, 'a4', 'בושם הרמס פריפיום גדול', 'member', v_koren);

  insert into public.tasks (section_id, position, title, assignee_kind, assignee_member_id) values
    (sec_tasks, 'a5', 'בושם דיור', 'member', v_haim);

  insert into public.tasks (section_id, position, title, due_at, assignee_kind, assignee_member_id) values
    (sec_tasks, 'a6', 'שיננית מכבידנט חולון', '2026-08-03', 'member', v_koren);

  insert into public.tasks (section_id, position, title, due_at, notes) values
    (sec_tasks, 'a7', 'הרברט סמואל מלון בירושלים', '2026-08-18', '18/8/26–20/8/26');

  insert into public.tasks (section_id, position, title, due_at, notes, emoji) values
    (sec_tasks, 'a8', 'אילת אסטרל מאריס', '2026-07-16', '16/7–19/7', '🏖️');

  -- ---------------------------------------------------------------------
  -- משימות עם ולואי (Louis)
  -- ---------------------------------------------------------------------
  insert into public.tasks (id, section_id, position, title, notes) values
    (task_september, sec_louis, 'a0', 'לקנות בחודש ספטמבר (9)', null);
  insert into public.tasks (section_id, parent_task_id, position, title) values
    (sec_louis, task_september, 'a0', 'כדור נגד פרעושים');

  insert into public.tasks (section_id, position, title) values
    (sec_louis, 'a1', 'חטיפי עוף');

  insert into public.tasks (section_id, position, title, due_at, is_completed, completed_at) values
    (sec_louis, 'a2', 'תספורת', '2026-06-30 12:00+00', true, '2026-06-30 12:00+00');

  -- ---------------------------------------------------------------------
  -- סופר פארם
  -- ---------------------------------------------------------------------
  insert into public.tasks (section_id, position, title) values
    (sec_pharm, 'a0', 'מצעים חדשים'),
    (sec_pharm, 'a1', 'חמוציות'),
    (sec_pharm, 'a2', 'בנפייבר');

  -- ---------------------------------------------------------------------
  -- AliExpress
  -- ---------------------------------------------------------------------
  insert into public.tasks (section_id, position, title) values
    (sec_ali, 'a0', 'בטריות להייר סטרייטנר'),
    (sec_ali, 'a1', 'בוסטר');

  -- ---------------------------------------------------------------------
  -- קניות בסופר
  -- ---------------------------------------------------------------------
  insert into public.tasks (section_id, position, title) values
    (sec_market, 'a0', 'נוטלה'),
    (sec_market, 'a1', 'עופות'),
    (sec_market, 'a2', 'לחמניות'),
    (sec_market, 'a3', 'דגים'),
    (sec_market, 'a4', 'פיתות כוסמין'),
    (sec_market, 'a5', 'פטריות'),
    (sec_market, 'a6', 'ג''ל גילוח לעור עדין'),
    (sec_market, 'a7', 'מרכך כביסה');

  insert into public.tasks (section_id, position, title, is_note, emoji) values
    (sec_market, 'a8', 'ירקות מהירקן', true, '🥬');

  insert into public.tasks (section_id, position, title) values
    (sec_market, 'a9', 'תפוז'),
    (sec_market, 'aA', 'תותים'),
    (sec_market, 'aB', 'פלפל חריף'),
    (sec_market, 'aC', 'בננות');

  insert into public.tasks (section_id, position, title, is_completed, completed_at) values
    (sec_market, 'aD', 'חציל', true, now()),
    (sec_market, 'aE', 'קישוא', true, now()),
    (sec_market, 'aF', 'עגבניות', true, now()),
    (sec_market, 'aG', 'בצל לבן', true, now());

  -- ---------------------------------------------------------------------
  -- להכין בבית
  -- ---------------------------------------------------------------------
  insert into public.tasks (section_id, position, title) values
    (sec_cooking, 'a0', 'לביבות'),
    (sec_cooking, 'a1', 'פשטידות'),
    (sec_cooking, 'a2', 'עוגיות');

  -- ---------------------------------------------------------------------
  -- מטלות בית (chores)
  -- ---------------------------------------------------------------------
  insert into public.chores (section_id, position, title, freq, weekdays) values
    (sec_chores, 'a0', 'שאיבת רצפה', 'daily', null),
    (sec_chores, 'a1', 'החלפת מצעים', 'weekly', null),
    (sec_chores, 'a2', 'שטיפת ריצפה', 'weekly', null),
    (sec_chores, 'a3', 'זריקת שקיות הזבל', 'as_needed', null),
    (sec_chores, 'a4', 'כביסות - הכנסה, תליה, קיפול', 'as_needed', null),
    (sec_chores, 'a5', 'ניקיון שירותים', 'daily', null),
    (sec_chores, 'a6', 'סידור הבית (סלון, חדרים, נעליים, בגדים)', 'daily', null),
    (sec_chores, 'a7', 'קניות סופר משלימות (חלב, ביצים...)', 'as_needed', null),
    (sec_chores, 'a8', 'ניקיון כיורים', 'as_needed', null),
    (sec_chores, 'a9', 'זירו קר למקרר', 'as_needed', null),
    (sec_chores, 'aA', 'ניקיון גז', 'as_needed', null),
    (sec_chores, 'aB', 'ניקיון מקרר', 'as_needed', null),
    (sec_chores, 'aC', 'הכנסת כלים למדיח ופינוי לארונות', 'as_needed', null),
    (sec_chores, 'aD', 'ניקיון אבק', 'weekly', null),
    (sec_chores, 'aE', 'ניקוי מטענים של מברשות שיניים', 'as_needed', null);

  insert into public.chores (section_id, position, title, freq, assignee_kind, emoji) values
    (sec_chores, 'aF', 'לשים לב לכמות האוכל בשק של לואי ולספר לסבא לפני שנגמר', 'as_needed', 'louis', '💙');

  -- ---------------------------------------------------------------------
  -- A note worth keeping, exactly as it was
  -- ---------------------------------------------------------------------
  insert into public.tasks (section_id, position, title, is_note) values
    (sec_love, 'a0',
     'קורן, אני אוהב אותך 💙 — חיים, גם אני אותך 💙 יריב, גם אני אותך 💙💙💙 יריב, גם אני אותךךך ❤️🩶💙',
     true);
end $$;
