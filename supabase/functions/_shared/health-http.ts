import { createClient } from "npm:@supabase/supabase-js@2.110.1";
export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-health-maintenance",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
export const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
export function adminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}
export async function requireUser(req: Request) {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("unauthorized");
  const admin = adminClient();
  const {
    data: { user },
    error,
  } = await admin.auth.getUser(token);
  if (error || !user) throw new Error("unauthorized");
  const { data: member } = await admin
    .from("members")
    .select("id")
    .eq("user_id", user.id)
    .maybeSingle();
  if (!member) throw new Error("unauthorized");
  const { data: release, error: releaseError } = await admin
    .from("health_release_state")
    .select("personal_access_ready")
    .eq("id", true)
    .single();
  if (releaseError || !release?.personal_access_ready)
    throw new Error("release_pending");
  return { admin, user, member };
}
export async function body(req: Request, limit = 20000) {
  const text = await req.text();
  if (text.length > limit) throw new Error("body_too_large");
  return JSON.parse(text);
}
export function failure(e: unknown) {
  const code = e instanceof Error ? e.message : "failed";
  const known = [
    "unauthorized",
    "invalid_input",
    "body_too_large",
    "not_configured",
    "release_pending",
    "rate_limited",
    "analysis_busy",
    "invalid_image",
    "not_found",
    "provider_failed",
    "invalid_output",
    "label_lookup_required",
  ];
  return json(
    { error: known.includes(code) ? code : "failed" },
    code === "unauthorized"
      ? 401
      : code === "not_configured" || code === "release_pending"
        ? 503
        : code === "rate_limited"
          ? 429
          : code === "analysis_busy"
            ? 409
            : code === "provider_failed"
              ? 502
              : 400,
  );
}

export async function referencedImages(
  admin: ReturnType<typeof adminClient>,
  owner?: string,
) {
  const used = new Set<string>();
  for (let offset = 0; ; offset += 500) {
    let query = admin
      .from("meals")
      .select("id,data")
      .is("deleted_at", null)
      .order("id")
      .range(offset, offset + 499);
    if (owner) query = query.eq("owner_user_id", owner);
    const { data, error } = await query;
    if (error) throw new Error("failed");
    for (const row of data ?? [])
      if (typeof row.data?.imagePath === "string") used.add(row.data.imagePath);
    if (!data || data.length < 500) break;
  }
  for (let offset=0;;offset+=500) {
    let query=admin.from("wellness_exercise_illustrations").select("exercise_id,image_path").order("owner_user_id").order("exercise_id").range(offset,offset+499);
    if(owner)query=query.eq("owner_user_id",owner);
    const {data,error}=await query;if(error)throw new Error("failed");
    for(const row of data??[])used.add(row.image_path);
    if(!data||data.length<500)break;
  }
  for(let offset=0;;offset+=500){
    let query=admin.from('wellness_training_examples').select('id,image_path').order('id').range(offset,offset+499);
    if(owner)query=query.eq('owner_user_id',owner);
    const {data,error}=await query;if(error)throw new Error('failed');
    for(const row of data??[])if(row.image_path)used.add(row.image_path);
    if(!data||data.length<500)break;
  }
  return used;
}
