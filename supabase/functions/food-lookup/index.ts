import {
  body,
  cors,
  failure,
  json,
  requireUser,
} from "../_shared/health-http.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const { admin, user } = await requireUser(req);
    const input = await body(req);
    const barcode = typeof input.barcode === "string" ? input.barcode : "";
    if (barcode && !/^\d{8,14}$/.test(barcode))
      throw new Error("invalid_input");
    if (!barcode) {
      const q =
        typeof input.query === "string" ? input.query.trim().slice(0, 100) : "";
      if (q.length < 2) return json({ foods: [] });
      // Escape LIKE wildcards; search-as-you-type never hits the external API.
      const safe = q.replace(/[\\%_]/g, "\\$&");
      const results = await Promise.all(
        ["name", "nameEn"].map((key) =>
          admin
            .from("food_catalog")
            .select("data")
            .ilike(`data->>${key}`, `%${safe}%`)
            .limit(30),
        ),
      );
      if (results.some((r) => r.error)) throw new Error("failed");
      return json({
        foods: Array.from(
          new Map(
            results
              .flatMap((r) => r.data ?? [])
              .map((r) => [r.data.id, r.data]),
          ).values(),
        ).slice(0, 30),
      });
    }
    const { data: personal } = await admin
      .from("personal_foods")
      .select("data")
      .eq("owner_user_id", user.id)
      .eq("data->>barcode", barcode)
      .is("deleted_at", null)
      .limit(1);
    if (personal?.length) return json({ foods: personal.map((r) => r.data) });
    const key = `off:${barcode}`;
    const { data: cached } = await admin
      .from("food_catalog")
      .select("data,updated_at")
      .eq("source_key", key)
      .maybeSingle();
    if (cached && Date.parse(cached.updated_at) > Date.now() - 30 * 86400000)
      return json({ foods: [cached.data] });
    let res: Response;
    try {
      res = await fetch(
        `https://world.openfoodfacts.org/api/v2/product/${barcode}.json?fields=product_name,product_name_he,nutriments,nutrition_data_per,serving_quantity,product_quantity_unit`,
        {
          headers: {
            "User-Agent":
              "KH-SmartHome/1.0 (personal nutrition; github.com/Haimindyk/smart-home)",
          },
          signal: AbortSignal.timeout(6000),
        },
      );
    } catch {
      if (cached) return json({ foods: [cached.data], stale: true });
      throw new Error("provider_failed");
    }
    if (!res.ok) {
      if (cached) return json({ foods: [cached.data], stale: true });
      throw new Error(res.status === 429 ? "rate_limited" : "provider_failed");
    }
    const result = await res.json();
    const p = result.product;
    const n = p?.nutriments;
    const value = (key: string) =>
      typeof n?.[key] === "number" && Number.isFinite(n[key]) && n[key] >= 0
        ? n[key]
        : null;
    const required = [
      "energy-kcal_100g",
      "proteins_100g",
      "carbohydrates_100g",
      "fat_100g",
    ];
    if (result.status !== 1 || required.some((k) => value(k) === null)) {
      const { data: known } = await admin
        .from("barcode_products")
        .select("product_name")
        .eq("barcode", barcode)
        .maybeSingle();
      return json({
        foods: [],
        name:
          p?.product_name_he ?? p?.product_name ?? known?.product_name ?? null,
        needsLabel: true,
      });
    }
    const data = {
      id: key,
      name: p.product_name_he || p.product_name || barcode,
      barcode,
      basis:
        p.nutrition_data_per === "100ml" || p.product_quantity_unit === "ml"
          ? "ml"
          : "g",
      source: "openfoodfacts",
      sourceId: `https://world.openfoodfacts.org/product/${barcode}`,
      per100: {
        kcal: value("energy-kcal_100g"),
        protein: value("proteins_100g"),
        carbs: value("carbohydrates_100g"),
        fat: value("fat_100g"),
        fiber: value("fiber_100g"),
        sugar: value("sugars_100g"),
        saturatedFat: value("saturated-fat_100g"),
        sodium:
          value("sodium_100g") === null ? null : value("sodium_100g")! * 1000,
      },
    };
    // OFF data stays a separately attributed source; user corrections never overwrite it.
    await admin.from("food_catalog").upsert({
      source_key: key,
      source: "openfoodfacts",
      data,
      attribution: "Open Food Facts — ODbL",
      updated_at: new Date().toISOString(),
    });
    return json({ foods: [data] });
  } catch (e) {
    return failure(e);
  }
});
