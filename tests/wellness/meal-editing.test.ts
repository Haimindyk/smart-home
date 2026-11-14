import { expect, it, vi, beforeEach } from "vitest";
import { mealItemSchema, payloadSchemas, type HealthRow } from "../../src/lib/health/model";
const mock = vi.hoisted(() => ({ state: {} as Record<string, unknown>, save: vi.fn() }));
vi.mock("../../src/lib/health/store", () => ({ useHealthStore: { getState: () => mock.state } }));
import { editedMealData, saveMealItems, repeatedMealData, saveRepeatedMeal } from "../../src/lib/health/meal-editing";

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

it("repeats mixed-unit source snapshots with fresh item IDs and no image/correction identity", () => {
  const mixed = { ...row, data: { ...row.data, items: [first, { ...second, food: { ...second.food, basis: "ml" as const }, quantity: 125 }] } };
  const copy = repeatedMealData(mixed, "2026-11-15");
  expect(copy.date).toBe("2026-11-15");
  expect(copy.kind).toBe("lunch");
  expect(copy.imagePath).toBeNull();
  expect(copy.aiEstimate).toBeUndefined();
  copy.items.forEach((item, index) => {
    expect(item.id).not.toBe(mixed.data.items[index].id);
    expect({ ...item, id: mixed.data.items[index].id }).toEqual(mixed.data.items[index]);
  });
  expect(mixed.data.items[1].quantity).toBe(125);
  expect(repeatedMealData({ ...row, data: { ...row.data, name: "" } }, "2026-11-15").name).toBe("אורז ודג");
  expect(repeatedMealData({ ...row, data: { ...row.data, name: "My lunch" } }, "2026-11-15").name).toBe("My lunch");
  expect(() => repeatedMealData(row, "2026-02-30")).toThrow();
});

it("uses a stable new record ID and accepts a completed retry without another write", async () => {
  const data = repeatedMealData(row, "2026-11-15"), id = crypto.randomUUID();
  mock.save.mockImplementation(async () => {
    const saved = { ...row, id, data, version: 1 };
    mock.state = { ...mock.state, data: { meals: [row, saved] } };
    throw new Error("cache_failed_after_queue");
  });
  expect((await saveRepeatedMeal(row, data, id)).id).toBe(id);
  expect((await saveRepeatedMeal(row, data, id)).id).toBe(id);
  expect(mock.save).toHaveBeenCalledTimes(1);
  expect(mock.save).toHaveBeenCalledWith("meals", data, undefined, id);
});

it("refuses repetition from stale or foreign rows and never overwrites an ID collision", async () => {
  const data = repeatedMealData(row, "2026-11-15"), id = crypto.randomUUID();
  await expect(saveRepeatedMeal({ ...row, version: 3 }, data, id)).rejects.toThrow("version_conflict");
  await expect(saveRepeatedMeal({ ...row, owner_user_id: "other" }, data, id)).rejects.toThrow("session_mismatch");
  mock.state = { ...mock.state, data: { meals: [row, { ...row, id }] } };
  await expect(saveRepeatedMeal(row, data, id)).rejects.toThrow("version_conflict");
  expect(mock.save).not.toHaveBeenCalled();
});
