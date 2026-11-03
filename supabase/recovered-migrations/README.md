# Applied migration source recovered from Supabase

These are the original SQL statements and migration versions read from the
existing project's `supabase_migrations.schema_migrations` table on 2026-11-03.
They were missing from GitHub. They have already been applied to the live
`smart-home-kh` project; recovery did not execute them again.

The existing `supabase/migrations/` files use the older 0001–0031 naming scheme,
while the live migration history uses timestamps. Keeping recovered statements
here avoids silently mixing those histories or rerunning already-applied SQL.
`human_notifications_only` was omitted because its source already exists in
`supabase/migrations/0031_human_notifications_only.sql`.

Before provisioning a fresh project or using automated database migration
commands, reconcile the original migrations and this archive into one reviewed
baseline. Some archived statements alter existing objects or perform one-time
updates, and must not be blindly rerun on the production database. No database
rows, credentials, or runtime secret values were exported.
