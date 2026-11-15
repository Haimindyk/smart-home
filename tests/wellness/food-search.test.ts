import { describe, expect, it, vi } from "vitest";
import { searchFoodNames } from "../../supabase/functions/_shared/food-search";
import { foodSchema } from "../../src/lib/health/model";
import tahini from "./fixtures/off-tahini-search.json";

function source(products: unknown[] = tahini.products) {
  return vi.fn<typeof fetch>(async (input) => {
    const url = new URL(String(input));
    if (url.hostname === "search.openfoodfacts.org") {
      return Response.json({
        hits: products.map((p) => ({ code: (p as { code: string }).code })),
      });
    }
    const code = url.pathname.match(/\/(\d+)\.json$/)?.[1];
    return Response.json({
      status: 1,
      product: products.find((p) => (p as { code: string }).code === code),
    });
  });
}

describe("explicit food-name search", () => {
  it("finds real Hebrew tahini products when the local catalog has no match", async () => {
    const fetcher = source();
    const r = await searchFoodNames("טחינה", [], fetcher);
    expect(r.fetched).toBe(true);
    expect(r.foods).toHaveLength(3);
    const foods = r.foods.map((f) => foodSchema.parse(f));
    expect(foods[1]).toMatchObject({
      name: "טחינה גולמית",
      basis: "g",
      source: "openfoodfacts",
      barcode: "7290017275345",
      per100: {
        kcal: 667,
        protein: 24,
        carbs: 2,
        fat: 60,
        sugar: 1,
        sodium: null,
      },
    });
    expect(foods[2].per100.sodium).toBe(220);
    const url = new URL(String(fetcher.mock.calls[0][0]));
    expect(url.searchParams.get("q")).toBe("טחינה");
    expect(url.searchParams.get("page_size")).toBe("8");
  });
  it("reuses and deduplicates cached foods without an external request", async () => {
    const fetcher = vi.fn();
    const food = { id: "local:1", name: "טחינה" };
    expect(await searchFoodNames("טחינה", [food, food], fetcher)).toEqual({
      foods: [food],
      fetched: false,
    });
    expect(fetcher).not.toHaveBeenCalled();
  });
  it("never invents missing macros or an unknown/per-serving basis", async () => {
    const p = tahini.products[0];
    const r = await searchFoodNames(
      "tahini",
      [],
      source([
        { ...p, code: "invalid" },
        { ...p, code: "12345678", nutrition_data_per: "serving" },
        {
          ...p,
          code: "23456789",
          nutriments: { ...p.nutriments, proteins_100g: undefined },
        },
        { ...p, code: "34567890", nutrition_data_per: "100ml" },
      ]),
    );
    expect(r.foods).toHaveLength(1);
    expect(r.foods[0]).toMatchObject({ basis: "ml", per100: { kcal: 689 } });
  });
  it("distinguishes source failures and rate limiting from an empty result", async () => {
    await expect(
      searchFoodNames(
        "טחינה",
        [],
        async () => new Response("", { status: 429 }),
      ),
    ).rejects.toThrow("rate_limited");
    await expect(
      searchFoodNames(
        "טחינה",
        [],
        async () => new Response("", { status: 503 }),
      ),
    ).rejects.toThrow("provider_failed");
    await expect(searchFoodNames("טחינה", [], async () => {
      throw new Error("timeout");
    })).rejects.toThrow("provider_failed");
    await expect(searchFoodNames("טחינה", [], async () => Response.json({})))
      .rejects.toThrow("provider_failed");
  });
  it("keeps the provider brand and usable records when another product is unavailable", async () => {
    const normal = source([
      { ...tahini.products[0], brands: "Example brand" },
      ...tahini.products.slice(1),
    ]);
    const fetcher: typeof fetch = async (input, init) =>
      String(input).includes(`/product/${tahini.products[1].code}.json`)
        ? new Response("", { status: 503 })
        : normal(input, init);
    const r = await searchFoodNames("טחינה", [], fetcher);
    expect(r.foods).toHaveLength(2);
    expect(r.foods[0]).toMatchObject({
      name: "טחינה · Example brand",
      per100: { kcal: 689, protein: 24 },
    });
  });
  it("bounds requests, filters duplicate products and allows a genuine empty result", async () => {
    const r = await searchFoodNames(
      "tahini",
      [],
      source(Array(50).fill(tahini.products[0])),
    );
    expect(r.foods).toHaveLength(1);
    expect(await searchFoodNames("tahini", [], source([]))).toEqual({
      foods: [],
      fetched: true,
    });
    const fetcher = vi.fn();
    await searchFoodNames(" ", [], fetcher);
    expect(fetcher).not.toHaveBeenCalled();
  });
});
