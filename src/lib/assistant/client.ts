import { createClient } from "@/lib/supabase/client";
import type { AssistantResponse } from "./types";

/** Thin wrapper around the `assistant` Edge Function — the only place this
 * app invokes an Edge Function directly from the client (send-push is only
 * ever invoked server-side, by a DB trigger). */
export async function askAssistant(input: {
  message?: string;
  imageBase64?: string;
  imageMimeType?: string;
  memberId?: string | null;
}): Promise<AssistantResponse | { error: string }> {
  const supabase = createClient();
  const { data, error } = await supabase.functions.invoke("assistant", {
    body: { intent: "chat", ...input },
  });
  if (error) return { error: "assistant_unreachable" };
  if (data?.error) return { error: data.error as string };
  return data as AssistantResponse;
}
