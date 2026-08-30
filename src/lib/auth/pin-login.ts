import { createClient } from "@/lib/supabase/client";

type PinLoginResult = { memberId: string } | { error: string };

/** Verifies a PIN server-side (see supabase/functions/pin-login) and, on a
 * match, establishes a real signed-in Supabase Auth session for that member
 * on this device — the identity board privacy (see migration 0034) actually
 * relies on, unlike the plain local "who picked this PIN" match this used
 * to be. */
export async function pinLogin(pin: string): Promise<PinLoginResult> {
  const supabase = createClient();
  const { data, error } = await supabase.functions.invoke("pin-login", { body: { pin } });
  if (error || !data || data.error) return { error: (data?.error as string) ?? "unreachable" };

  const { error: sessionError } = await supabase.auth.setSession({
    access_token: data.access_token as string,
    refresh_token: data.refresh_token as string,
  });
  if (sessionError) return { error: "session_failed" };

  return { memberId: data.memberId as string };
}
