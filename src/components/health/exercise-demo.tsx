"use client";
import Image from "next/image";
import demos from "@/lib/health/exercise-demos.json";
import type { Exercise } from "@/lib/health/model";
import { useHealthText } from "@/lib/health/i18n";
export function resolveExerciseDemo(exercise: Pick<Exercise,"name"|"demoId">) {
  const name=exercise.name.trim().toLowerCase();
  return demos.find(d=>d.id===exercise.demoId) ?? demos.find(d=>[d.he,d.en,d.id].some(n=>n.toLowerCase()===name));
}
export function ExerciseThumbnail({exercise}: {exercise: Exercise}) {
  const demo=resolveExerciseDemo(exercise);
  return demo ? <Image src={`/exercises/${demo.id}-1.jpg`} alt={exercise.name} width={80} height={80} className="exercise-thumb"/> : <span className="exercise-thumb flex items-center justify-center bg-muted" aria-hidden="true">↗</span>;
}
export function ExerciseDemo({exercise}: {exercise: Exercise}) {
  const h=useHealthText();
  const demo=resolveExerciseDemo(exercise);
  return <div className="exercise-demo">
    {demo ? <><div className="exercise-demo-frames">{[0,1].map(i=><figure key={i}><a href={`/exercises/${demo.id}-${i}.jpg`} target="_blank" rel="noreferrer"><Image src={`/exercises/${demo.id}-${i}.jpg`} width={360} height={360} alt={`${exercise.name} — ${i===0?h("עמדה 1","Position 1"):h("עמדה 2","Position 2")}`} className="h-28 w-full rounded-xl bg-white object-contain"/></a><figcaption>{i===0?h("עמדה 1","Position 1"):h("עמדה 2","Position 2")}</figcaption></figure>)}</div></> : <p className="text-sm text-muted-foreground">{h("טרם נבחרה הדגמה לתרגיל הזה. אפשר לבחור המחשה בעריכת התכנית.","No demonstration selected. Choose one in the plan editor.")}</p>}
    <p className="mt-2 text-xs text-muted-foreground">{exercise.sets} × {exercise.holdSeconds ? `${exercise.holdSeconds}–${exercise.holdSecondsMax??exercise.holdSeconds} ${h("שניות","seconds")}` : `${exercise.reps}${exercise.repMax?`–${exercise.repMax}`:""} ${h("חזרות","reps")}`} · {exercise.loadUnknown ? h("משקל לא הוגדר","Load not specified") : `${exercise.weight}${exercise.weightMax?`–${exercise.weightMax}`:""} kg`} · {h("מנוחה","Rest")} {exercise.rest}s</p>
    {exercise.alternativeDemoId&&<details className="mt-3"><summary className="text-sm font-semibold">{h("הדגמת החלופה", "Alternative demonstration")}</summary>{demos.filter(d=>d.id===exercise.alternativeDemoId).map(d=><div key={d.id}><p className="my-2 font-semibold">{h(d.he,d.en)}</p><div className="exercise-demo-frames">{[0,1].map(i=><Image key={i} src={`/exercises/${d.id}-${i}.jpg`} width={360} height={360} alt={`${h(d.he,d.en)} ${i===0?h("עמדה 1","Position 1"):h("עמדה 2","Position 2")}`} className="h-28 w-full rounded-xl object-contain"/>)}</div><p className="mt-2 text-sm">{d.cues}</p></div>)}</details>}
    {(exercise.notes||demo?.cues)&&<details className="mt-2 text-xs text-muted-foreground"><summary>{h("דגשי ביצוע", "Technique notes")}</summary><p className="mt-2 whitespace-pre-wrap leading-6">{exercise.notes||demo?.cues}</p>{demo&&<a className="mt-2 inline-block underline" href="https://github.com/yuhonas/free-exercise-db" target="_blank" rel="noreferrer">free-exercise-db · public domain</a>}</details>}

  </div>;
}
