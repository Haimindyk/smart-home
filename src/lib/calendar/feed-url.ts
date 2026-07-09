import { supabaseUrl } from "@/lib/supabase/env";

/** Public URL of the calendar-feed Edge Function (see
 * supabase/functions/calendar-feed) — a subscribable ICS feed of
 * family_events, no login required, same as the rest of this app. */
export function calendarFeedUrl(): string {
  return `${supabaseUrl.replace(".supabase.co", ".functions.supabase.co")}/calendar-feed`;
}
