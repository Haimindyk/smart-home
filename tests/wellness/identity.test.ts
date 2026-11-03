import { beforeEach, it, expect, vi } from "vitest";
const client = vi.hoisted(() => ({
  auth: { getSession: vi.fn() },
  functions: { invoke: vi.fn() },
}));
vi.mock("@/lib/supabase/client", () => ({ createClient: () => client }));
import { healthFunction } from "../../src/lib/health/api";
beforeEach(() => vi.clearAllMocks());
it("does not send private AI content if the auth session switched during the request", async () => {
  client.auth.getSession.mockResolvedValue({
    data: { session: { user: { id: "owner-b" }, access_token: "synthetic-b" } },
  });
  await expect(
    healthFunction(
      "wellness-ai",
      { description: "private meal for owner A" },
      "owner-a",
    ),
  ).rejects.toThrow("session_mismatch");
  expect(client.functions.invoke).not.toHaveBeenCalled();
});
it("sends the captured owner token when the authenticated owner matches", async () => {
  client.auth.getSession.mockResolvedValue({
    data: { session: { user: { id: "owner-a" }, access_token: "synthetic-a" } },
  });
  client.functions.invoke.mockResolvedValue({
    data: { available: true },
    error: null,
  });
  expect(
    await healthFunction("wellness-ai", { action: "capabilities" }, "owner-a"),
  ).toEqual({ available: true });
  expect(client.functions.invoke).toHaveBeenCalledWith(
    "wellness-ai",
    expect.objectContaining({
      headers: { Authorization: "Bearer synthetic-a" },
    }),
  );
});
