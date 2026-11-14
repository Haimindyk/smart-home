import { expect, it, vi, beforeEach } from "vitest";
import { mealItemSchema, payloadSchemas, type HealthRow } from "../../src/lib/health/model";
const mock = vi.hoisted(() => ({ state: {} as Record<string, unknown>, save: vi.fn() }));
vi.mock("../../src/lib/health/store", () => ({ useHealthStore: { getState: () => mock.state } }));
import { editedMealData, saveMealItems } from "../../src/lib/health/meal-editing";

const item = (id: string, name: string) => mealItemSchema.parse({ id, quantity: 50, food: { id: name, name, basis: "g", source: "label", sourceId: "printed-confirmed", per100: { kcal: 200, protein: 10, carbs: 20, fat: 5 } } });
const first = item("11111111-1111-4111-8111-111111111111", "אורז"), second = item("22222222-2222-4222-8222-222222222222", "דג");
const row = { id: "meal", owner_user_id: "owner", version: 4, data: payloadSchemas.meals.parse({ date: "2026-11-14", kind: "lunch", name: "אורז ודג", items: [first, second], imagePath: "owner/photo.jpg", aiEstimate: { analysisId: "33333333-3333-4333-8333-333333333333" } }) } as HealthRow<"meals">;

beforeEach(() => { mock.save.mockReset(); mock.state = { owner: "owner", data: { meals: [row] }, save: mock.save }; });

it("updates totals' input and automatic title without changing retained food values or metadata", () => {
  const edited = editedMealData(row, [second]);
  expect(edited.name).toBe("דג");
  expect(edited.items[0]).toEqual(second);
  expect(edited.imagePath).toBe(row.data.imagePath);
  expect(edited.aiEstimate).toEqual(row.data.aiEstimate);
  expect(editedMealData({ ...row, data: { ...row.data, name: "My custom lunch" } }, [second]).name).toBe("My custom lunch");
});

it("refuses empty meals, duplicate item IDs and too many items before enqueueing", async () => {
  for (const items of [[], [first, first], Array.from({ length: 101 }, () => first)]) {
    await expect(saveMealItems(row, items)).rejects.toThrow();
  }
  expect(mock.save).not.toHaveBeenCalled();
});

it("uses the latest matching-version owner row and the existing mutation queue", async () => {
  mock.save.mockResolvedValue({ ...row, version: 5 });
  await saveMealItems(row, [first]);
  expect(mock.save).toHaveBeenCalledWith("meals", expect.objectContaining({ items: [first] }), row);
});

it("rejects stale undo/edit attempts and changed sessions without writing", async () => {
  mock.state = { ...mock.state, data: { meals: [{ ...row, version: 5 }] } };
  await expect(saveMealItems(row, [first])).rejects.toThrow("version_conflict");
  mock.state = { ...mock.state, owner: "other" };
  await expect(saveMealItems(row, [first])).rejects.toThrow("session_mismatch");
  expect(mock.save).not.toHaveBeenCalled();
});

it("recognizes an exact edit already accepted before a later local-cache error", async () => {
  const accepted = { ...row, data: editedMealData(row, [first]), version: 5 };
  mock.save.mockImplementation(async () => {
    mock.state = { ...mock.state, data: { meals: [accepted] } };
    throw new Error("cache_failed_after_queue");
  });
  expect(await saveMealItems(row, [first])).toEqual(accepted);
  expect(mock.save).toHaveBeenCalledTimes(1);
});

it("keeps a genuine failed write visible when no matching edit was accepted", async () => {
  mock.save.mockRejectedValue(new Error("queue_failed"));
  await expect(saveMealItems(row, [first])).rejects.toThrow("queue_failed");
});
