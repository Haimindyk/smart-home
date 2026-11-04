import {
  body,
  cors,
  failure,
  json,
  requireUser,
} from "../_shared/health-http.ts";
import { openFoodFactsProduct } from "../_shared/food-product.ts";
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
    const labelOnly = input.labelOnly === true;
    let personalQuery = admin
      .from("personal_foods")
      .select("data")
      .eq("owner_user_id", user.id)
      .eq("data->>barcode", barcode)
      .is("deleted_at", null)
      .limit(1);
    if (labelOnly)
      personalQuery = personalQuery
        .eq("data->>source", "label")
        .eq("data->>sourceId", "label:printed-confirmed:v1");
    const { data: personal, error: personalError } = await personalQuery;
    if (personalError) throw new Error("failed");
    if (personal?.length) return json({ foods: personal.map((r) => r.data) });
    const key = `off:v2:${barcode}`;
    const { data: cached } = await admin
      .from("food_catalog")
      .select("data,updated_at")
      .eq("source_key", key)
      .maybeSingle();
    const validCached =
      cached?.data?.source === "openfoodfacts" &&
      ["g", "ml"].includes(cached?.data?.basis)
        ? cached
        : null;
    if (
      validCached &&
      Date.parse(validCached.updated_at) > Date.now() - 30 * 86400000
    )
      return json({ foods: [validCached.data] });
    let res: Response;
    try {
      res = await fetch(
        `https://world.openfoodfacts.org/api/v2/product/${barcode}.json?fields=product_name,product_name_he,nutriments,nutrition_data_per`,
        {
          headers: {
            "User-Agent":
              "KH-SmartHome/1.0 (personal nutrition; github.com/Haimindyk/smart-home)",
          },
          signal: AbortSignal.timeout(6000),
        },
      );
    } catch {
      if (validCached) return json({ foods: [validCached.data], stale: true });
      throw new Error("provider_failed");
    }
    if (!res.ok) {
      if (validCached) return json({ foods: [validCached.data], stale: true });
      throw new Error(res.status === 429 ? "rate_limited" : "provider_failed");
    }
    const result = await res.json();
    const p = result.product;
    const data = openFoodFactsProduct(result, barcode);
    if (!data) {
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
