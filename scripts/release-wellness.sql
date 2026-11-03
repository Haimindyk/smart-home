-- Executed by psql --single-transaction from the exact merged Git commit.
-- Do not replay the recovered historical migrations against the live project.
select pg_advisory_xact_lock(hashtextextended('smart-home:wellness-release',0));
select exists(select 1 from supabase_migrations.schema_migrations where version='20261103200306') as already_applied \gset
\if :already_applied
\echo 'Wellness migration already applied; no schema change.'
\else
\ir ../supabase/migrations/20261103200306_wellness_ai.sql
insert into supabase_migrations.schema_migrations(version,name,statements)
values('20261103200306','wellness_ai',array['Applied from reviewed Git merge; see repository migration 20261103200306_wellness_ai.sql']);
\endif

select exists(select 1 from supabase_migrations.schema_migrations where version='20261103203820') as training_applied \gset
\if :training_applied
\echo 'Training-data migration already applied.'
\else
\ir ../supabase/migrations/20261103203820_wellness_training_data.sql
insert into supabase_migrations.schema_migrations(version,name,statements)
values('20261103203820','wellness_training_data',array['Applied from reviewed Git merge; see repository migration 20261103203820_wellness_training_data.sql']);
\endif
