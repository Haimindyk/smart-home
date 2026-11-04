import { describe, it, expect, vi } from "vitest";
import {
  createProvider,
  MODELS,
} from "../../supabase/functions/_shared/wellness-provider";
const settings: Record<string, string> = {
  WELLNESS_AI_ENABLED: "true",
  CLOUDFLARE_FREE_ONLY: "true",
  CLOUDFLARE_ACCOUNT_ID: "a".repeat(32),
  CLOUDFLARE_AI_TOKEN: "test-only",
};
const env = (key: string) => settings[key];
describe("free-only provider adapter", () => {
  it("never contacts a provider unless explicitly enabled with the free-only guard", async () => {
    const request = vi.fn();
    await expect(
      createProvider(
        (k) => (k === "CLOUDFLARE_FREE_ONLY" ? "false" : env(k)),
        request,
      ).structured("test", {}),
    ).rejects.toThrow("not_configured");
    expect(request).not.toHaveBeenCalled();
  });
  it("uses the allowlisted model, bounded structured output, and no retry", async () => {
    const request = vi.fn<typeof fetch>(
      async () =>
        new Response(
          JSON.stringify({
            success: true,
            result: { response: '{"ok":true}' },
          }),
        ),
    );
    expect(
      await createProvider(env, request).structured("Return JSON", {
        description: "אכלתי ביצה",
      }),
    ).toEqual({ ok: true });
    expect(request).toHaveBeenCalledTimes(1);
    expect(request.mock.calls[0][0]).toContain(MODELS.text);
    const options = request.mock.calls[0][1] as RequestInit;
    const payload = JSON.parse(String(options.body));
    expect(payload.max_tokens).toBe(2500);
    expect(payload.response_format.type).toBe("json_object");
  });
  it("passes the real JSON schema and accepts the provider's object response", async () => {
    const request = vi.fn<typeof fetch>(
      async () =>
        new Response(
          JSON.stringify({
            result: { response: { items: [] } },
            success: true,
          }),
        ),
    );
    const schema = { type: "object", properties: { items: { type: "array" } } };
    expect(
      await createProvider(env, request).structured(
        "Extract",
        {},
        100,
        "nutrition_text",
        schema,
      ),
    ).toEqual({ items: [] });
    const payload = JSON.parse(String(request.mock.calls[0][1]!.body));
    expect(payload.response_format).toEqual({
      type: "json_schema",
      json_schema: schema,
    });
  });
  it("uses the explicitly selected photo normalizer only for photo requests", async () => {
    const request = vi.fn<typeof fetch>(
      async () =>
        new Response(
          JSON.stringify({
            result: { response: { foods: [] } },
            success: true,
          }),
        ),
    );
    await createProvider(env, request).structured(
      "Photo",
      {},
      1800,
      "nutrition_text",
      { type: "object" },
      true,
    );
    expect(request.mock.calls[0][0]).toContain(MODELS.mealText);
    expect(request).toHaveBeenCalledTimes(1);
  });
  it("stops on quota exhaustion with no paid fallback", async () => {
    const request = vi.fn<typeof fetch>(
      async () => new Response("", { status: 429 }),
    );
    await expect(
      createProvider(env, request).structured("test", {}),
    ).rejects.toThrow("rate_limited");
    expect(request).toHaveBeenCalledTimes(1);
  });
  it("rejects malformed model JSON and non-image illustration data", async () => {
    await expect(
      createProvider(
        env,
        async () =>
          new Response(JSON.stringify({ result: { response: "oops" } })),
      ).structured("test", {}),
    ).rejects.toThrow("invalid_output");
    await expect(
      createProvider(
        env,
        async () =>
          new Response(
            JSON.stringify({ result: { image: btoa("not a JPEG") } }),
          ),
      ).illustration("test"),
    ).rejects.toThrow("invalid_output");
  });
});
