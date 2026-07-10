-- Hebrew conjugates second-person verbs/pronouns by the *listener's*
-- gender (את/אתה, חושבת/חושב), not just the speaker's. Mika's own
-- feminine self-reference (MIKA_PERSONA in the Edge Function) says nothing
-- about who she's talking TO — without this, she defaulted to addressing
-- everyone in feminine form, which read as wrong for the household's male
-- members (e.g. קורן was addressed as if a girl).
alter table public.members add column gender text check (gender in ('male', 'female'));

update public.members set gender = 'male' where display_name in ('קורן', 'חיים', 'יריבי');
update public.members set gender = 'female' where email = 'assistant@kh.family';
