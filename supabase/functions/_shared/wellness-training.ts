import { body, cors, failure, json, requireUser } from "./health-http.ts";
import { adult, parsePreferences, text } from "./wellness-core.ts";
import { resolveCatalogExercise } from "./exercise-catalog.ts";
const uuid = (v: unknown) => {
  if (typeof v !== "string" || !/^[-a-f0-9]{36}$/i.test(v))
    throw new Error("invalid_input");
  return v;
};
const checked = <T>(r: { data: T; error: unknown }) => {
  if (r.error) throw new Error("failed");
  return r.data;
};
export async function handleTraining(req: Request) {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const { admin, user } = await requireUser(req),
      input = await body(req);
    const consent = checked(
      await admin
        .from("wellness_training_consents")
        .select("enabled,subject_group")
        .eq("owner_user_id", user.id)
        .maybeSingle(),
    );
    if (input.action === "status")
      return json({
        enabled: consent?.enabled === true,
        policy: "wellness-training-v1",
        count:
          checked(
            await admin
              .from("wellness_training_examples")
              .select("id")
              .eq("owner_user_id", user.id),
          )?.length ?? 0,
      });
    if (input.action === "consent") {
      if (
        typeof input.enabled !== "boolean" ||
        input.policy !== "wellness-training-v1"
      )
        throw new Error("invalid_input");
      if (input.enabled) {
        const profile = checked(
          await admin
            .from("health_profiles")
            .select("data")
            .eq("owner_user_id", user.id)
            .is("deleted_at", null)
            .maybeSingle(),
        )?.data;
        if (!profile || !adult(profile, new Date().toISOString().slice(0, 10)))
          throw new Error("adult_profile_required");
      }
      checked(
        await admin.rpc("wellness_training_consent", {
          p_owner: user.id,
          p_enabled: input.enabled,
        }),
      );
      return json({ ok: true });
    }
    if (input.action === "remove") {
      checked(
        await admin
          .from("wellness_training_examples")
          .delete()
          .eq("id", uuid(input.exampleId))
          .eq("owner_user_id", user.id),
      );
      return json({ ok: true });
    }
    if (!consent?.enabled) throw new Error("training_consent_required");
    if (input.action === "export") {
      const rows =
        checked(
          await admin
            .from("wellness_training_examples")
            .select("id,task,source_id,example,image_path")
            .eq("owner_user_id", user.id)
            .order("id")
            .limit(200),
        ) ?? [];
      const examples = await Promise.all(
        rows.map(async (row) => ({
          id: row.id,
          task: row.task,
          subject_group: consent.subject_group,
          source_group: Array.from(
            new Uint8Array(
              await crypto.subtle.digest(
                "SHA-256",
                new TextEncoder().encode(row.source_id),
              ),
            ),
          )
            .map((x) => x.toString(16).padStart(2, "0"))
            .join(""),
          consent_policy: "wellness-training-v1",
          consent_active: true,
          reviewed: false,
          synthetic: false,
          ...row.example,
          ...(row.image_path
            ? {
                image: {
                  path: `images/${row.id}.jpg`,
                  sha256: "requires_owner_download",
                },
              }
            : {}),
        })),
      );
      return json({ examples });
    }
    if (input.action === "image") {
      const row = checked(
        await admin
          .from("wellness_training_examples")
          .select("image_path")
          .eq("id", uuid(input.exampleId))
          .eq("owner_user_id", user.id)
          .maybeSingle(),
      );
      if (!row?.image_path) throw new Error("not_found");
      const { data, error } = await admin.storage
        .from("health-images")
        .download(row.image_path);
      if (error || !data || data.size > 5242880)
        throw new Error("invalid_image");
      return new Response(data, {
        headers: {
          ...cors,
          "Content-Type": data.type,
          "Cache-Control": "no-store",
        },
      });
    }
    if (
      input.action !== "submit" ||
      input.confirmShare !== true ||
      !["nutrition_text", "nutrition_photo", "coach_program"].includes(
        input.task,
      )
    )
      throw new Error("invalid_input");
    const adultProfile = checked(
      await admin
        .from("health_profiles")
        .select("data")
        .eq("owner_user_id", user.id)
        .is("deleted_at", null)
        .maybeSingle(),
    )?.data;
    if (
      !adultProfile ||
      !adult(adultProfile, new Date().toISOString().slice(0, 10))
    )
      throw new Error("adult_profile_required");
    const source = uuid(input.sourceId),
      description = text(input.description ?? "", 2500);
    let example: Record<string, unknown>,
      image: string | null = null;
    if (input.task.startsWith("nutrition_")) {
      const meal = checked(
        await admin
          .from("meals")
          .select("data")
          .eq("id", source)
          .eq("owner_user_id", user.id)
          .is("deleted_at", null)
          .maybeSingle(),
      )?.data;
      if (!meal) throw new Error("not_found");
      if (input.task === "nutrition_text" && !description)
        throw new Error("invalid_input");
      if (input.task === "nutrition_photo") {
        image = meal.imagePath;
        if (
          !image ||
          !image.startsWith(user.id + "/") ||
          image.includes("..") ||
          image.includes("\\")
        )
          throw new Error("invalid_image");
      }
      example = {
        label_quality: input.weighed === true ? "weighed" : "user_corrected",
        input: {
          description,
          mode: input.task === "nutrition_text" ? "text" : "meal",
        },
        target: {
          items: meal.items.map(
            (i: {
              food: {
                name: string;
                basis: string;
                per100: unknown;
                source: string;
              };
              quantity: number;
            }) => ({
              name: i.food.name,
              basis: i.food.basis,
              per100: i.food.per100,
              quantity: i.quantity,
              source: i.food.source,
            }),
          ),
        },
      };
    } else {
      const profile = checked(
        await admin
          .from("health_profiles")
          .select("data")
          .eq("owner_user_id", user.id)
          .is("deleted_at", null)
          .maybeSingle(),
      )?.data;
      const preferences = parsePreferences(profile?.trainingPreferences);
      const plans =
        checked(
          await admin
            .from("workout_plans")
            .select("id,data")
            .eq("owner_user_id", user.id)
            .is("deleted_at", null),
        ) ?? [];
      const selected = plans.find((p) => p.id === source);
      if (!selected) throw new Error("not_found");
      const group = selected.data.programId
        ? plans
            .filter((p) => p.data.programId === selected.data.programId)
            .sort((a, b) => a.data.cycleIndex - b.data.cycleIndex)
        : [selected];
      const target = group.map((p) => ({
        name: `Program ${p.data.cycleIndex ?? 0}`,
        notes: "",
        exercises: p.data.exercises.map(
          (e: {
            name: string;
            catalogId?: string;
            sets: number;
            reps: number;
            rest: number;
          }) => {
            const c = resolveCatalogExercise(e.name, e.catalogId);
            if (!c) throw new Error("exercise_clarification_required");
            return {
              catalogId: c.id,
              sets: e.sets,
              reps: e.reps,
              rest: e.rest,
            };
          },
        ),
      }));
      example = {
        label_quality: "user_corrected",
        input: { preferences: { ...preferences, notes: "" }, description },
        target: { plans: target },
      };
    }
    const result = await admin.rpc("wellness_training_submit", {
      p_owner: user.id,
      p_task: input.task,
      p_source: source,
      p_example: example,
      p_image: image,
    });
    if (result.error) {
      if (result.error.message.includes("training_consent_required"))
        throw new Error("training_consent_required");
      if (result.error.message.includes("training_limit"))
        throw new Error("training_limit");
      throw new Error("failed");
    }
    return json({ id: result.data, reviewed: false });
  } catch (e) {
    const code = e instanceof Error ? e.message : "failed";
    if (
      [
        "training_consent_required",
        "training_limit",
        "exercise_clarification_required",
        "adult_profile_required",
      ].includes(code)
    )
      return json({ error: code }, 400);
    return failure(e);
  }
}
