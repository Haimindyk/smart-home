import { openFoodFactsProduct } from "./food-product.ts";

// Explicit name searches only. Reuse validated catalog matches before making a
// bounded public-data request; nutrition never comes from a language model.
export async function searchFoodNames<T extends { id: string }>(
  query: string,
  cached: T[],
  fetcher: typeof fetch = fetch,
) {
  const q = query.trim().slice(0, 100);
  if (q.length < 2) return { foods: [] as T[], fetched: false as const };
  if (cached.length) {
    return {
      foods: [...new Map(cached.map((f) => [f.id, f])).values()].slice(0, 30),
      fetched: false as const,
    };
  }
  // Open Food Facts can take 10-25 s when it is busy; a short limit made name searches fail.
  const signal = AbortSignal.timeout(25000);
  const headers = {
    "User-Agent":
      "KH-SmartHome/1.0 (personal nutrition; github.com/Haimindyk/smart-home)",
  };
  const url = new URL("https://search.openfoodfacts.org/search");
  url.search = new URLSearchParams({
    q: q.replace(/([+\-!(){}\[\]^"~*?:\\/])/g, "\\$1"),
    langs: "he,en",
    page_size: "8",
    fields: "code",
  }).toString();
  let response: Response;
  try {
    response = await fetcher(url, {
      headers,
      signal,
    });
  } catch {
    throw new Error("provider_failed");
  }
  if (!response.ok) {
    throw new Error(
      response.status === 429 ? "rate_limited" : "provider_failed",
    );
  }
  let raw: { hits?: unknown[] };
  try {
    raw = await response.json();
  } catch {
    throw new Error("provider_failed");
  }
  if (!raw || !Array.isArray(raw.hits)) throw new Error("provider_failed");
  const codes = [
    ...new Set(
      raw.hits.slice(0, 8).flatMap((p) => {
        if (!p || typeof p !== "object") return [];
        const code = (p as { code?: unknown }).code;
        if (typeof code !== "string" || !/^\d{8,14}$/.test(code)) return [];
        return [code];
      }),
    ),
  ];
  // The search index omits nutrition_data_per. Fetch full source records rather
  // than assuming that its *_100g fields establish a gram/volume basis.
  const records = await Promise.all(codes.map(async (code) => {
    try {
      const product = await fetcher(
        `https://world.openfoodfacts.org/api/v2/product/${code}.json?fields=product_name,product_name_he,brands,nutriments,nutrition_data_per`,
        { headers, signal },
      );
      if (!product.ok) {
        return {
          food: null,
          error: product.status === 429 ? "rate_limited" : "provider_failed",
        };
      }
      const rawProduct = await product.json(),
        food = openFoodFactsProduct(rawProduct, code);
      const brand = rawProduct?.product?.brands;
      if (
        food && typeof brand === "string" && brand.trim() &&
        brand.length <= 100 &&
        !food.name.toLowerCase().includes(brand.trim().toLowerCase())
      ) {
        const name = `${food.name} · ${brand.trim()}`;
        if (name.length <= 200) food.name = name;
      }
      return { food, error: null };
    } catch {
      return { food: null, error: "provider_failed" };
    }
  }));
  const foods = records.flatMap((r) => r.food ? [r.food] : []);
  if (!foods.length && records.some((r) => r.error)) {
    throw new Error(
      records.some((r) => r.error === "rate_limited")
        ? "rate_limited"
        : "provider_failed",
    );
  }
  return {
    foods: [...new Map(foods.map((f) => [f.id, f])).values()],
    fetched: true as const,
  };
}
