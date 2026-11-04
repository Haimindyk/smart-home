import { describe, it, expect } from "vitest";
import {
  parseChatAnswer,
  symptomReply,
  chatMessage,
  chatVersion,
  historyForModel,
  diarySummary,
  type ChatTurn,
} from "../../supabase/functions/_shared/wellness-chat-core";
describe("chat data contract and privacy", () => {
  it("accepts only bounded replies and known demonstration identities", () => {
    expect(
      parseChatAnswer({
        reply: "שאלה טובה",
        topic: "technique",
        exerciseIds: ["Plank"],
        followUps: ["איך להתקדם?"],
      }),
    ).toMatchObject({ topic: "technique" });
    for (const patch of [
      { reply: "" },
      { reply: "x".repeat(6001) },
      { exerciseIds: ["invented"] },
      { topic: "medical_prescription" },
      { followUps: Array(4).fill("q") },
    ])
      expect(() =>
        parseChatAnswer({ reply: "ok", topic: "general", ...patch }),
      ).toThrow();
  });
  it("rejects empty, overlong messages and fractional revisions", () => {
    expect(chatMessage(" שלום ")).toBe("שלום");
    expect(() => chatMessage(" ")).toThrow();
    expect(() => chatMessage("x".repeat(2001))).toThrow();
    expect(() => chatVersion(0.5)).toThrow();
  });
  it("bounds recent context and does not send row IDs or sharing metadata", () => {
    const turn = {
      id: "private-id",
      user_text: "question",
      answer: parseChatAnswer({ reply: "answer", topic: "general" }),
      shared_diary: true,
      created_at: "2026-11-04",
    };
    const history = historyForModel(Array.from({ length: 30 }, () => turn));
    expect(history).toHaveLength(12);
    expect(JSON.stringify(history)).not.toContain("private-id");
    expect(
      historyForModel([
        {
          ...turn,
          answer: { ...turn.answer, reply: "x".repeat(12001) },
        } as ChatTurn,
      ]),
    ).toHaveLength(0);
  });
  it("reports logged totals with completeness unknown, while excluding unrelated personal fields", () => {
    const summary = diarySummary(
      "2026-11-04",
      [
        {
          data: {
            name: "private meal note",
            items: [
              {
                quantity: 200,
                food: { per100: { kcal: 100, protein: 10, carbs: 20, fat: 1 } },
              },
            ],
          },
        },
      ],
      { kcal: 2000, protein: 100, carbs: 250, fat: 60, private: "not shared" },
      [
        {
          data: {
            date: "2026-11-03",
            status: "completed",
            notes: "private workout note",
            exercises: [
              {
                name: "Squat",
                performed: [
                  { done: true, reps: 8, weight: 20 },
                  { done: false, reps: 8, weight: 999 },
                ],
              },
            ],
          },
        },
      ],
    );
    expect(summary.loggedTotals.kcal).toBe(200);
    expect(summary.dayLoggingCompleteness).toBe("unknown");
    expect(JSON.stringify(summary)).not.toMatch(
      /private meal|private workout|not shared|999/,
    );
    expect(diarySummary("2026-11-04", [], null, [])).toMatchObject({
      loggedMealCount: 0,
      dayLoggingCompleteness: "unknown",
    });
  });
});

describe("symptom routing", () => {
  it("never generates exercise adjustments for a painful movement", () => {
    for (const message of ["כואבת לי הברך בסקוואט, להוסיף משקל?", "I have knee pain, should I push through?", "נפצעתי באימון"]) {
      const answer = symptomReply(message);
      expect(answer).not.toBeNull();
      expect(answer!.exerciseIds).toEqual([]);
      expect(answer!.reply).toMatch(/הפסק|stop/);
      expect(() => parseChatAnswer(answer)).not.toThrow();
    }
  });
  it("routes urgent symptoms to urgent help without a diagnosis", () => {
    expect(symptomReply("יש כאב בחזה וקוצר נשימה")!.reply).toContain("101");
    expect(symptomReply("chest pain while exercising")!.reply).toContain("urgent medical help");
  });
  it("leaves ordinary exercise and nutrition questions to the coach", () => {
    expect(symptomReply("איך עושים סקוואט? ועצות לארוחת ערב" )).toBeNull();
  });
});
