"use client";
import { useRef, useState } from "react";
import { ArrowRight, Check, Sparkles, Target, Footprints, TrendingUp } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useHealthText } from "@/lib/health/i18n";
import { ageOnDate, calculateGoal, goalForDate, localDate } from "@/lib/health/calculations";
import { payloadSchemas, type HealthProfile, type Payload } from "@/lib/health/model";
import { Field, ErrorText } from "./shared";

export function ProfileJourney({profile, onChange, goals, onSave, busy}: {
  profile: HealthProfile;
  onChange: (profile: HealthProfile) => void;
  goals: Payload<"nutrition_goals">[];
  onSave: (goal: Payload<"nutrition_goals">) => Promise<void>;
  busy: boolean;
}) {
  const h = useHealthText();
  const today = localDate(profile.timezone);
  const existing = goalForDate(goals,today);
  const heading = useRef<HTMLHeadingElement>(null);
  function focusStep() { requestAnimationFrame(()=>heading.current?.focus()); }
  const [step,setStep] = useState(0);
  const [manual,setManual] = useState(existing?.method === "manual");
  const [date,setDate] = useState(today);
  const [custom,setCustom] = useState(existing ?? {date:today,kcal:2000,protein:100,carbs:250,fat:65,method:"manual" as const});
  const [error,setError] = useState<string|null>(null);
  const patch = (p: Partial<HealthProfile>) => onChange({...profile,...p});
  let age: number|null=null, suggested: Payload<"nutrition_goals">|null=null;
  try {if(profile.birthDate) age=ageOnDate(profile.birthDate,today);} catch {}
  try {if(profile.birthDate) suggested=calculateGoal(profile,date);} catch {}
  const titles=[h("מה המטרה שלך?", "What brings you here?"),h("נכיר אותך קצת", "Let's make it personal"),h("התכנית שמתאימה לך", "Your daily game plan")];
  const value = manual ? custom : suggested;
  function next() {
    if(step===1 && !manual && (age===null || age<18 || !profile.height || !profile.weight || !profile.physiology)) {setError("adult_profile_required");return;}
    setError(null);setStep(s=>s+1);focusStep();
  }
  async function finish() {
    setError(null);
    if(profile.birthDate && age===null){setError("invalid_birth_date");return;}
    if(!value){setError("adult_profile_required");return;}
    const parsed=payloadSchemas.nutrition_goals.safeParse({...value,date,method:manual?"manual":"calculated"});
    if(!parsed.success){setError("invalid_input");return;}
    await onSave(parsed.data);
  }
  return <section className="profile-journey">
    <div className="journey-top"><span className="journey-badge"><Sparkles size={15}/>{h("מותאם לך", "MADE FOR YOU")}</span><span>{step+1} / 3</span></div>
    <div className="journey-progress" aria-label={h("התקדמות מילוי הפרופיל", "Profile progress")}>{titles.map((title,i)=><span key={title} className={i<=step?"done":""}/>)}</div>
    <h2 ref={heading} tabIndex={-1} className="mt-7 outline-none text-3xl font-bold tracking-tight">{titles[step]}</h2>
    <p className="mt-3 mb-7 text-sm leading-7 text-muted-foreground">{[h("בוחרים כיוון. אנחנו נדאג לחישוב היעדים.", "Pick a direction. We'll work out your targets."),h("כמה פרטים כדי להתאים את התזונה לגוף שלך. הגיל מתעדכן לבד לפי תאריך הלידה.", "A few details to tailor your targets. Your age stays up to date from your birthday."),h("בוחרים את קצב היום. הקלוריות והערכים מחושבים עבורך, ואפשר תמיד לבחור אחרת.", "Choose your daily pace. Calories and macros are calculated for you; you can always choose your own.")][step]}</p>
    <ErrorText error={error}/>
    {step===0 && <div className="grid gap-3">{([
      ["lose",h("ירידה מתונה במשקל", "Lose weight gradually"),h("צעדים קטנים, הרגלים שנשארים", "Small steps, lasting habits"),Footprints],
      ["maintain",h("לשמור ולהרגיש טוב", "Maintain & feel good"),h("איזון שמתאים לחיים שלך", "Balance that fits your life"),Target],
      ["gain",h("להתחזק ולבנות", "Get stronger & build"),h("לתמוך באימונים ובהתקדמות", "Fuel your training and progress"),TrendingUp],
    ] as const).map(([key,title,subtitle,Icon])=><button key={key} aria-pressed={profile.objective===key} onClick={()=>patch({objective:key})} className={`journey-choice ${profile.objective===key?"selected":""}`}><span className="choice-icon"><Icon size={23}/></span><span className="flex-1"><strong>{title}</strong><small>{subtitle}</small></span>{profile.objective===key && <Check size={19}/>}</button>)}</div>}
    {step===1 && <div className="grid gap-5">
      <Field label={h("תאריך לידה", "Date of birth")} type="date" autoComplete="bday" max={today} value={profile.birthDate??""} onChange={e=>patch({birthDate:e.target.value||null,age:null})}/>
      {age!==null && <p className="text-sm text-muted-foreground">{h("הגיל שלך היום:", "Your age today:")} <strong>{age}</strong></p>}
      <div className="grid grid-cols-2 gap-4"><Field label={h("גובה בס״מ", "Height (cm)")} type="number" min={80} max={250} value={profile.height??""} onChange={e=>patch({height:e.target.value?+e.target.value:null})}/><Field label={h("משקל בק״ג", "Weight (kg)")} type="number" min={20} max={400} step="0.1" value={profile.weight??""} onChange={e=>patch({weight:e.target.value?+e.target.value:null})}/></div>
      <fieldset><legend className="mb-3 text-sm">{h("נתון פיזיולוגי לחישוב", "Physiology used for the formula")}</legend><div className="grid grid-cols-2 gap-3">{([['male',h("זכר", "Male")],['female',h("נקבה", "Female")]] as const).map(([key,label])=><button key={key} aria-pressed={profile.physiology===key} onClick={()=>patch({physiology:key})} className={`journey-choice justify-center ${profile.physiology===key?"selected":""}`}>{label}</button>)}</div></fieldset>
      <p className="text-xs text-muted-foreground">{h("ללא פרופיל מלא או מתחת לגיל 18 אפשר לבחור יעדים ידניים.", "Without a complete adult profile, choose manual targets.")}</p>
    </div>}
    {step===2 && <div className="grid gap-5">
      <fieldset><legend className="mb-3 text-sm font-semibold">{h("כמה תנועה יש ביום שלך?", "How active is your day?")}</legend><div className="grid grid-cols-2 gap-3">{([
        ['sedentary',h("בעיקר בישיבה", "Mostly seated")],['light',h("קצת תנועה", "Light activity")],['moderate',h("בתנועה קבועה", "Regular activity")],['high',h("יום פעיל מאוד", "Very active")],
      ] as const).map(([key,label])=><button key={key} aria-pressed={profile.activity===key} onClick={()=>patch({activity:key})} className={`journey-choice ${profile.activity===key?"selected":""}`}>{label}</button>)}</div></fieldset>
      {value ? <div className="journey-targets"><p className="text-xs text-muted-foreground">{manual?h("היעד שבחרת", "YOUR TARGET"):h("היעד היומי שלך", "YOUR DAILY TARGET")}</p><p className="my-2 text-4xl font-bold">{value.kcal.toLocaleString()} <small className="text-sm font-normal">kcal</small></p><div className="grid grid-cols-3 gap-3">{([['protein',h("חלבון", "Protein")],['carbs',h("פחמימות", "Carbs")],['fat',h("שומן", "Fat")]] as const).map(([key,label])=><p key={key}><strong>{value[key]}g</strong><span className="block text-xs text-muted-foreground">{label}</span></p>)}</div></div> : <p className="rounded-2xl bg-muted p-4 text-sm">{h("השלמת הפרופיל תפתח חישוב אוטומטי. אפשר גם לבחור יעדים ידניים.", "Complete your profile for automatic targets, or choose manual targets.")}</p>}
      <Field label={h("היעד בתוקף מתאריך", "Goal effective from")} type="date" value={date} onChange={e=>{if(e.target.value)setDate(e.target.value)}}/>
    </div>}
    <label className="my-6 flex items-center justify-between gap-4 rounded-2xl border p-4 text-sm"><span>{h("אני רוצה לבחור יעדים בעצמי", "I want to choose my own targets")}</span><input type="checkbox" checked={manual} onChange={e=>{if(e.target.checked&&suggested)setCustom(suggested);setManual(e.target.checked);setError(null)}}/></label>
    {manual && step===2 && <div className="mb-5 grid grid-cols-2 gap-4">{([['kcal',h("קלוריות", "Calories")],['protein',h("חלבון בגרם", "Protein (g)")],['carbs',h("פחמימות בגרם", "Carbs (g)")],['fat',h("שומן בגרם", "Fat (g)")]] as const).map(([key,label])=><Field key={key} label={label} type="number" min={key==='kcal'?500:0} value={custom[key]} onChange={e=>setCustom(g=>({...g,[key]:+e.target.value}))}/>)}</div>}
    <div className="flex gap-3">{step>0&&<Button variant="outline" disabled={busy} onClick={()=>{setStep(s=>s-1);setError(null);focusStep()}}>{h("חזרה", "Back")}</Button>}<Button className="min-h-12 flex-1" disabled={busy} onClick={()=>{if(step<2)next();else void finish()}}>{busy?h("שומר…", "Saving…"):step<2?h("ממשיכים", "Continue"):h("שמירת הפרופיל והיעדים", "Save profile & targets")}{step<2 && <span className="rtl:rotate-180"><ArrowRight size={17}/></span>}{step===2&&<Check size={17}/>}</Button></div>
    <p className="mt-5 text-xs leading-6 text-muted-foreground">{h("החישוב למבוגרים לפי Mifflin–St Jeor הוא נקודת התחלה שאפשר לשנות, לא הנחיה רפואית. אימונים אינם מוסיפים קלוריות ליעד.", "Adult Mifflin–St Jeor estimates are an editable starting point, not medical advice. Workouts do not add calories to the target.")}</p>
  </section>;
}
