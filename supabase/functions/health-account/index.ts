import {
  body,
  cors,
  failure,
  json,
  requireUser,
  referencedImages,
} from "../_shared/health-http.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const { admin, user } = await requireUser(req);
    const input = await body(req);
    if (input.action === "register") {
      if (
        typeof input.name !== "string" ||
        typeof input.pin !== "string" ||
        !/^\d{4}$/.test(input.pin) ||
        typeof input.emoji !== "string" ||
        typeof input.color !== "string"
      )
        throw new Error("invalid_input");
      const { data: id, error } = await admin.rpc("register_health_member", {
        p_name: input.name,
        p_pin: input.pin,
        p_emoji: input.emoji,
        p_color: input.color,
      });
      if (error)
        return json(
          { error: error.code === "23505" ? "pin_taken" : "invalid_input" },
          400,
        );
      const { data } = await admin
        .from("members")
        .select(
          "id,email,user_id,display_name,avatar_emoji,color,locale,created_at,updated_at,avatar_photo_url,gender,is_ai_companion_target,last_chat_at",
        )
        .eq("id", id)
        .single();
      return json({ member: data });
    }
    if (input.action === "cleanup") {
      const { data: files, error } = await admin.storage
        .from("health-images")
        .list(user.id, { limit: 1000 });
      if (error) throw new Error("failed");
      const used = await referencedImages(admin, user.id);
      const stale = (files ?? [])
        .filter(
          (f) =>
            !used.has(`${user.id}/${f.name}`) &&
            Date.parse(f.created_at ?? "") < Date.now() - 86400000,
        )
        .map((f) => `${user.id}/${f.name}`);
      if (stale.length) await admin.storage.from("health-images").remove(stale);
      return json({ ok: true });
    }
    if (
      input.action === "delete" &&
      ["nutrition", "workouts", "all"].includes(input.module)
    ) {
      const { error } = await admin.rpc("health_delete_module", {
        p_owner: user.id,
        p_module: input.module,
      });
      if (error) throw new Error("failed");
      // Delete only orphans: nutrition deletion must preserve workout illustrations,
      // and workout deletion must preserve saved meal photos. List before removing.
      const used=await referencedImages(admin,user.id),stale:string[]=[];
      for(let offset=0;;offset+=100){
        const {data:files,error}=await admin.storage.from("health-images").list(user.id,{limit:100,offset});
        if(error)throw new Error("failed");
        for(const f of files??[])if(!used.has(`${user.id}/${f.name}`))stale.push(`${user.id}/${f.name}`);
        if(!files||files.length<100)break;
      }
      for(let i=0;i<stale.length;i+=100){const {error}=await admin.storage.from("health-images").remove(stale.slice(i,i+100));if(error)throw new Error("failed");}
      return json({ ok: true });
    }
    throw new Error("invalid_input");
  } catch (e) {
    return failure(e);
  }
});
