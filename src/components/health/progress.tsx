"use client";
import { useState } from "react";
import { useHealthStore } from "@/lib/health/store";
import {
  dateRange,
  goalForDate,
  mealNutrients,
  workoutVolume,
} from "@/lib/health/calculations";
import { useHealthText } from "@/lib/health/i18n";
import { Panel, SelectField, Empty, round } from "./shared";
import { Button } from "@/components/ui/button";
function Chart({
  title,
  points,
  unit,
}: {
  title: string;
  points: { date: string; value: number | null }[];
  unit: string;
}) {
  const h = useHealthText();
  const values = points.flatMap((p) => (p.value === null ? [] : [p.value]));
  if (!values.length)
    return (
      <Panel title={title}>
        <Empty>{h("אין מספיק נתונים להצגה", "No data to display yet")}</Empty>
      </Panel>
    );
  const min = Math.min(...values),
    max = Math.max(...values),
    range = Math.max(1, max - min);
  const path = points
    .map((p, i) => {
      if (p.value === null) return "";
      const x = 32 + (i * 536) / Math.max(1, points.length - 1),
        y = 150 - ((p.value - min) * 110) / range;
      const command = i > 0 && points[i - 1].value !== null ? "L" : "M";
      return `${command}${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");
  return (
    <Panel title={title}>
      <svg
        role="img"
        aria-label={`${title} (${unit})`}
        viewBox="0 0 600 200"
        className="w-full text-primary"
      >
        <title>{title}</title>
        <line
          x1="32"
          y1="160"
          x2="568"
          y2="160"
          stroke="currentColor"
          opacity=".2"
        />
        <path d={path} fill="none" stroke="currentColor" strokeWidth="3" />
        {points.map((p, i) =>
          p.value === null ? null : (
            <circle
              key={p.date + String(i)}
              cx={32 + (i * 536) / Math.max(1, points.length - 1)}
              cy={150 - ((p.value - min) * 110) / range}
              r="3"
              fill="currentColor"
            />
          ),
        )}
        <text x="32" y="185" fontSize="12" fill="currentColor">
          {points[0]?.date.slice(5)}
        </text>
        <text x="510" y="185" fontSize="12" fill="currentColor">
          {points.at(-1)?.date.slice(5)}
        </text>
      </svg>
      <p className="text-sm text-muted-foreground">
        {round(min)}–{round(max)} {unit}
      </p>
      <details className="mt-3 text-sm">
        <summary>{h("טבלת נתונים", "Data table")}</summary>
        <table className="mt-2 w-full">
          <thead>
            <tr>
              <th scope="col" className="text-start">
                {h("תאריך", "Date")}
              </th>
              <th scope="col" className="text-end">
                {unit}
              </th>
            </tr>
          </thead>
          <tbody>
            {points.map((p, i) => (
              <tr key={p.date + String(i)}>
                <td>{p.date}</td>
                <td className="text-end tabular-nums">{round(p.value)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </details>
    </Panel>
  );
}
export function HealthProgress({ date }: { date: string }) {
  const h = useHealthText();
  const data = useHealthStore((s) => s.data),
    remove = useHealthStore((s) => s.remove);
  const [days, setDays] = useState(30),
    [exercise, setExercise] = useState("");
  const dates = dateRange(date, days),
    allowed = new Set(dates);
  const calories = dates.map((d) => {
    const meals = data.meals.filter((m) => m.data.date === d);
    return {
      date: d,
      value: meals.length
        ? meals.reduce((s, m) => s + mealNutrients(m.data.items).kcal, 0)
        : null,
    };
  });
  const weights = dates.map((d) => ({
    date: d,
    value: data.weight_logs.find((w) => w.data.date === d)?.data.weight ?? null,
  }));
  const weekly = data.weight_logs.filter((w) =>
    new Set(dateRange(date, 7)).has(w.data.date),
  );
  const sessions = data.workout_sessions.filter(
    (s) =>
      allowed.has(s.data.date) &&
      ["completed", "partial"].includes(s.data.status),
  );
  const completed = sessions.filter(
    (s) => s.data.status === "completed",
  ).length;
  const scheduled = dates.filter((d) =>
    data.workout_plans.some(
      (p) =>
        !p.data.archived &&
        p.data.days.includes(new Date(`${d}T12:00:00`).getDay()),
    ),
  ).length;
  const doneDays = new Set(
    sessions
      .filter((s) => s.data.status === "completed")
      .map((s) => s.data.date),
  );
  const adherence = dates.filter(
    (d) =>
      doneDays.has(d) &&
      data.workout_plans.some(
        (p) =>
          !p.data.archived &&
          p.data.days.includes(new Date(`${d}T12:00:00`).getDay()),
      ),
  ).length;
  const names = Array.from(
    new Set(sessions.flatMap((s) => s.data.exercises.map((e) => e.name))),
  );
  const selected = exercise || names[0] || "";
  const timed = sessions.some(s=>s.data.exercises.some(e=>e.name===selected&&!!e.holdSeconds));
  const exercisePoints = sessions
    .flatMap((s) =>
      s.data.exercises
        .filter(
          (e) =>
            e.name === selected &&
            e.kind === "strength" &&
            !e.skipped &&
            e.performed.some((v) => v.done),
        )
        .map((e) => ({
          date: s.data.date,
          value: Math.max(
            ...e.performed.filter((v) => v.done).map((v) => e.holdSeconds ? (v.seconds??0) : v.weight),
          ),
        })),
    )
    .sort((a, b) => a.date.localeCompare(b.date));
  return (
    <div className="grid gap-5">
      <SelectField
        label={h("תקופה עד התאריך שנבחר", "Period ending on selected date")}
        value={days}
        onChange={(e) => setDays(+e.target.value)}
      >
        <option value={7}>{h("שבוע", "Week")}</option>
        <option value={30}>{h("30 ימים", "30 days")}</option>
      </SelectField>
      <div className="grid grid-cols-2 gap-3">
        <Panel title={h("אימונים שהושלמו", "Completed workouts")}>
          <strong className="text-3xl">{completed}</strong>
          <p className="mt-2 text-xs text-muted-foreground">
            {h("ועוד אימונים חלקיים", "Plus partial workouts")}:{" "}
            {sessions.length - completed}
          </p>
        </Panel>
        <Panel title={h("עמידה בתכנון", "Schedule adherence")}>
          <strong className="text-3xl">
            {scheduled ? Math.round((adherence / scheduled) * 100) + "%" : "—"}
          </strong>
          <p className="mt-2 text-xs text-muted-foreground">
            {h("לפי הימים בתכנון הנוכחי", "Based on current scheduled days")}
          </p>
        </Panel>
      </div>
      {data.health_profiles[0]?.data.nutritionEnabled && (
        <>
          <Chart
            title={h("קלוריות שדווחו", "Logged calories")}
            points={calories}
            unit="kcal"
          />
          <Panel title={h("צריכה מול יעד יומי", "Intake vs daily goal")}>
            <div className="max-h-64 overflow-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr>
                    <th scope="col">{h("תאריך", "Date")}</th>
                    <th scope="col">{h("צריכה", "Intake")}</th>
                    <th scope="col">{h("יעד", "Goal")}</th>
                  </tr>
                </thead>
                <tbody>
                  {calories.map((p) => (
                    <tr key={p.date}>
                      <td className="p-1 text-center">{p.date}</td>
                      <td className="p-1 text-center">{round(p.value)}</td>
                      <td className="p-1 text-center">
                        {round(
                          goalForDate(
                            data.nutrition_goals.map((g) => g.data),
                            p.date,
                          )?.kcal,
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Panel>
          <Chart
            title={h("מעקב משקל", "Weight history")}
            points={weights}
            unit="kg"
          />
          <Panel title={h("שקילות וממוצע שבועי", "Weigh-ins & weekly average")}>
            <p>
              {h("ממוצע 7 ימים אחרונים", "Last 7 days average")}:{" "}
              {weekly.length
                ? (
                    weekly.reduce((s, w) => s + w.data.weight, 0) /
                    weekly.length
                  ).toFixed(1)
                : "—"}{" "}
              kg
            </p>
            {data.weight_logs
              .filter((w) => allowed.has(w.data.date))
              .map((w) => (
                <div key={w.id} className="mt-2 flex justify-between text-sm">
                  <span>
                    {w.data.date} · {w.data.weight} kg
                  </span>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => {
                      if (window.confirm(h("למחוק שקילה?", "Delete weigh-in?")))
                        void remove("weight_logs", w);
                    }}
                  >
                    {h("מחיקה", "Delete")}
                  </Button>
                </div>
              ))}
          </Panel>
        </>
      )}
      {data.health_profiles[0]?.data.workoutsEnabled && (
        <>
          <Chart
            title={h(
              "נפח אימון מסטים שבוצעו",
              "Workout volume from completed sets",
            )}
            points={sessions
              .filter((s) => !s.data.quick)
              .map((s) => ({
                date: s.data.date,
                value: workoutVolume(s.data.exercises),
              }))
              .sort((a, b) => a.date.localeCompare(b.date))}
            unit="kg"
          />
          {names.length > 0 && (
            <SelectField
              label={h("התקדמות בתרגיל", "Exercise progress")}
              value={selected}
              onChange={(e) => setExercise(e.target.value)}
            >
              {names.map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </SelectField>
          )}
          <Chart
            title={timed ? h("החזקה ארוכה ביותר שבוצעה", "Longest completed hold") : h("משקל מרבי בסט שבוצע", "Maximum weight in completed sets")}
            points={exercisePoints}
            unit={timed ? "s" : "kg"}
          />
          <Panel title={h("חזרות וביצועים", "Reps & performances")}>
            <div className="max-h-64 overflow-auto text-sm">
              {sessions.flatMap((s) =>
                s.data.exercises
                  .filter((e) => e.name === selected && !e.skipped)
                  .map((e) => (
                    <p className="mb-2" key={s.id + e.id}>
                      {s.data.date} ·{" "}
                      {e.performed
                        .filter((v) => v.done)
                        .map((v) =>
                          e.holdSeconds ? `${v.seconds??0} s` : e.kind === "strength"
                            ? `${v.reps} × ${v.weight} kg`
                            : `${v.duration} min / ${v.distance} km`,
                        )
                        .join(" · ") || "—"}
                    </p>
                  )),
              )}
            </div>
          </Panel>
        </>
      )}
    </div>
  );
}
