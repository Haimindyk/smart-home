"use client";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { useHealthStore } from "@/lib/health/store";
import { healthFunction } from "@/lib/health/api";
import { useHealthText } from "@/lib/health/i18n";
import { Panel, Field, SelectField, ErrorText } from "./shared";
async function training<T>(input: Record<string, unknown>): Promise<T> {
  const owner = useHealthStore.getState().owner;
  if (!owner) throw new Error("session_required");
  const result = await healthFunction<T>("wellness-training", input, owner);
  if (useHealthStore.getState().owner !== owner)
    throw new Error("session_mismatch");
  return result;
}
export function TrainingData() {
  const h = useHealthText(),
    owner = useHealthStore((s) => s.owner),
    data = useHealthStore((s) => s.data);
  const [status, setStatus] = useState<{
      enabled: boolean;
      count: number;
    } | null>(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState<string | null>(null),
    [notice, setNotice] = useState("");
  const [task, setTask] = useState("nutrition_text"),
    [source, setSource] = useState(""),
    [description, setDescription] = useState(""),
    [confirmed, setConfirmed] = useState(false),
    [weighed, setWeighed] = useState(false);
  useEffect(() => {
    let cancelled = false;
    void training<{ enabled: boolean; count: number }>({ action: "status" })
      .then((r) => {
        if (!cancelled) setStatus(r);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [owner]);
  async function perform(action: () => Promise<void>) {
    setBusy(true);
    setError(null);
    setNotice("");
    try {
      await action();
      setStatus(await training({ action: "status" }));
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setBusy(false);
    }
  }
  const rows = task === "coach_program" ? data.workout_plans : data.meals;
  return (
    <Panel title={h("עזרה באימון המודלים שלנו", "Help train our models")}>
      <div className="grid gap-3 text-sm leading-7">
        <p>
          {h(
            "זו הסכמה נפרדת מעיבוד בקשות ב־AI, והיא כבויה כברירת מחדל. רק דוגמאות שתבחרו ותאשרו יישמרו לבדיקה ולאימון המודלים של האפליקציה. לא משתפים אוטומטית את כל היומן, ולא משתמשים בנתונים לאימון מודלי הספק.",
            "This is separate from AI processing and is off by default. Only examples you explicitly choose and approve are kept for review and training of the app’s models. Your whole diary is never collected automatically, and examples are not used to train the provider’s base models.",
          )}
        </p>
        <p className="text-xs text-muted-foreground">
          {h(
            "דוגמאות עשויות להיבדק על ידי מי שמפתח ומאמן את המודל. אל תכללו שמות, פנים או מידע רפואי. ביטול ההסכמה מוחק את הדוגמאות מהמאגר; הוא לא יכול להוציא מידע ממשקלים שכבר אומנו. גרסאות שהשתמשו בדוגמאות שבוטלו יצטרכו לצאת משימוש ולהיות מאומנות מחדש.",
            "Model developers/reviewers may inspect contributed examples. Exclude names, faces and medical information. Revoking consent deletes stored examples; it cannot remove information from already-trained weights. Affected model versions must be retired and retrained.",
          )}
        </p>
        <ErrorText error={error} />
        {notice && <p role="status">{notice}</p>}
        {!status ? (
          <p>
            {h(
              "איסוף הדוגמאות יהיה זמין לאחר עדכון השרת.",
              "Contributions become available after the backend update.",
            )}
          </p>
        ) : (
          <>
            <p>
              {h("דוגמאות שבחרת לשתף:", "Examples you chose to contribute:")}{" "}
              {status.count}
            </p>
            <Button
              variant="outline"
              disabled={busy}
              onClick={() =>
                void perform(async () => {
                  await training({
                    action: "consent",
                    enabled: !status.enabled,
                    policy: "wellness-training-v1",
                  });
                })
              }
            >
              {status.enabled
                ? h(
                    "ביטול הסכמה ומחיקת הדוגמאות",
                    "Revoke consent and delete examples",
                  )
                : h(
                    "מאשר/ת השתתפות באימון המודלים שלנו",
                    "Opt in to training our models",
                  )}
            </Button>
            {status.enabled && (
              <>
                <SelectField
                  label={h("איזו דוגמה לשתף?", "Example type")}
                  value={task}
                  onChange={(e) => {
                    setTask(e.target.value);
                    setSource("");
                    setConfirmed(false);
                  }}
                >
                  <option value="nutrition_text">
                    {h(
                      "תיאור ארוחה והמרכיבים שתיקנתי",
                      "Meal description and corrected foods",
                    )}
                  </option>
                  <option value="nutrition_photo">
                    {h(
                      "תמונה שנשמרה וערכי הארוחה",
                      "Retained meal photo and nutrition",
                    )}
                  </option>
                  <option value="coach_program">
                    {h("תוכנית אימון שאישרתי", "A workout program I approved")}
                  </option>
                </SelectField>
                <SelectField
                  label={h("בחירת רשומה מהיומן שלי", "Choose a saved record")}
                  value={source}
                  onChange={(e) => {
                    setSource(e.target.value);
                    setConfirmed(false);
                  }}
                >
                  <option value="">{h("בחירה", "Choose")}</option>
                  {rows.map((r) => (
                    <option key={r.id} value={r.id}>
                      {"date" in r.data ? r.data.date + " · " : ""}
                      {r.data.name || h("ארוחה", "Meal")}
                    </option>
                  ))}
                </SelectField>
                <Field
                  label={h(
                    "תיאור הבקשה המקורי, בלי מידע מזהה",
                    "Original request without identifying information",
                  )}
                  maxLength={2500}
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                />
                {task !== "coach_program" && (
                  <label className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      checked={weighed}
                      onChange={(e) => setWeighed(e.target.checked)}
                    />
                    {h(
                      "כל כמויות המרכיבים נמדדו במשקל, ולא הוערכו",
                      "All ingredient amounts were weighed, not estimated",
                    )}
                  </label>
                )}
                {task === "nutrition_photo" && (
                  <p className="text-xs">
                    {h(
                      "נדרשת תמונה שבחרת לשמור בארוחה. בשיתוף היא תישמר גם כדוגמת אימון עד ביטול ההסכמה או מחיקת הנתונים.",
                      "Requires a photo you chose to keep with the meal. Once shared it is also retained as a training example until consent is revoked or the data is deleted.",
                    )}
                  </p>
                )}
                <label className="flex items-start gap-2">
                  <input
                    className="mt-2"
                    type="checkbox"
                    checked={confirmed}
                    onChange={(e) => setConfirmed(e.target.checked)}
                  />
                  {h(
                    "בדקתי את הרשומה ואני מאשר/ת לשתף את הדוגמה הזו לצורך אימון.",
                    "I reviewed this record and approve sharing this specific example for training.",
                  )}
                </label>
                <Button
                  disabled={
                    busy ||
                    !confirmed ||
                    !source ||
                    (task === "nutrition_text" && !description.trim())
                  }
                  onClick={() =>
                    void perform(async () => {
                      await training({
                        action: "submit",
                        task,
                        sourceId: source,
                        description,
                        weighed,
                        confirmShare: true,
                      });
                      setConfirmed(false);
                      setNotice(
                        h(
                          "הדוגמה נשמרה לבדיקה. היא עדיין אינה נתון אימון מאומת.",
                          "Saved for review. This is not yet a verified training label.",
                        ),
                      );
                    })
                  }
                >
                  {h("שיתוף הדוגמה שבחרתי", "Contribute this example")}
                </Button>
                <Button
                  variant="ghost"
                  disabled={busy || !status.count}
                  onClick={() =>
                    void perform(async () => {
                      const result = await training({ action: "export" });
                      const url = URL.createObjectURL(
                        new Blob([JSON.stringify(result, null, 2)], {
                          type: "application/json",
                        }),
                      );
                      const a = document.createElement("a");
                      a.href = url;
                      a.download = "my-wellness-training-submissions.json";
                      a.click();
                      URL.revokeObjectURL(url);
                    })
                  }
                >
                  {h(
                    "ייצוא הדוגמאות שלי (מטא־נתונים ללא תמונות)",
                    "Export my examples (metadata without images)",
                  )}
                </Button>
              </>
            )}
          </>
        )}
      </div>
    </Panel>
  );
}
