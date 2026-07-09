import { supabaseUrl } from "@/lib/supabase/env";

/** Public URL of the calendar-feed Edge Function (see
 * supabase/functions/calendar-feed) — a subscribable ICS feed of
 * family_events, no login required, same as the rest of this app. */
export function calendarFeedUrl(): string {
  return `${supabaseUrl.replace(".supabase.co", ".functions.supabase.co")}/calendar-feed`;
}

/** Same feed, but as a webcal:// URI — tapping this (rather than a plain
 * https:// link) is what makes iOS/macOS Calendar and many Android calendar
 * apps recognize it as "subscribe to this calendar" and open their own
 * add-subscription screen directly, instead of just downloading/opening the
 * raw .ics text with no obvious next step. */
export function calendarWebcalUrl(): string {
  return calendarFeedUrl().replace(/^https?:\/\//, "webcal://");
}
