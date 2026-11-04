"use client";
import { useId } from "react";
import type {
  InputHTMLAttributes,
  ReactNode,
  SelectHTMLAttributes,
} from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useHealthText } from "@/lib/health/i18n";
export function Panel({
  title,
  children,
  action,
}: {
  title: string;
  children: ReactNode;
  action?: ReactNode;
}) {
  return (
    <section className="health-panel rounded-2xl border bg-card p-4 shadow-sm sm:p-5">
      <div className="mb-4 flex items-center justify-between gap-2">
        <h2 className="text-lg font-semibold">{title}</h2>
        {action}
      </div>
      {children}
    </section>
  );
}
export function Field({
  label,
  ...props
}: InputHTMLAttributes<HTMLInputElement> & { label: string }) {
  const id = useId();
  return (
    <label htmlFor={id} className="grid min-w-0 gap-1.5 text-sm">
      <span className="text-muted-foreground">{label}</span>
      <Input id={id} {...props} />
    </label>
  );
}
export function SelectField({
  label,
  children,
  ...props
}: SelectHTMLAttributes<HTMLSelectElement> & { label: string }) {
  const id = useId();
  return (
    <div className="grid min-w-0 gap-1.5 text-sm">
      <label htmlFor={id} className="text-muted-foreground">
        {label}
      </label>
      <select
        id={id}
        className="h-10 w-full rounded-lg border bg-background px-3"
        {...props}
      >
        {children}
      </select>
    </div>
  );
}
export function Empty({ children }: { children: ReactNode }) {
  return (
    <p className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
      {children}
    </p>
  );
}
export function ErrorText({ error }: { error: string | null }) {
  const h = useHealthText();
  if (!error) return null;
  const messages: Record<string, string> = {
    chat_changed:h("השיחה השתנתה במכשיר אחר. בדקו את ההיסטוריה לפני שליחה חוזרת; הטיוטה נשמרה.","The conversation changed on another device. Check the history before resending; your draft is preserved."),
    sync_required: h("יש להמתין לסנכרון השינויים לפני שימוש במאמן.", "Wait for changes to sync before using the coach."),
    online_required: h("השימוש ב־AI דורש חיבור לאינטרנט.", "AI requires an internet connection."),
    consent_required: h("יש לאשר עיבוד ב־AI בהגדרות.", "Enable AI processing in Settings."),
    quota_exhausted: h("המכסה החינמית להיום נוצלה. אפשר להמשיך ידנית ולנסות מחר.", "Today's free allowance is used. Continue manually and try tomorrow."),
    request_conflict: h("הבקשה השתנתה. יש להכין הצעה חדשה.", "This request changed. Prepare a new proposal."),
    exercise_clarification_required: h("יש לבחור תרגיל מזוהה מהקטלוג כדי להכין איור.", "Choose an identified catalog exercise to create an illustration."),
    unbalanced_program: h("ההצעה לא כיסתה את קבוצות התנועה והדגשים שבחרת. נסו שוב או ערכו ידנית.", "The proposal missed required movement patterns or priorities. Retry or edit manually."),
    program_too_long: h("ההצעה ארוכה מהזמן שבחרת. נסו שוב או התאימו את משך האימון.", "The proposal exceeds your time budget. Retry or adjust the workout duration."),
    unsafe_progression: h("אין מספיק ביצועים ומשוב שמצדיקים את העלאת העומס שהוצעה. לא נשמר שינוי.", "There is insufficient performance and feedback to justify this progression. No change was saved."),
    training_consent_required:h("יש לאשר השתתפות נפרדת באימון המודלים.","Opt in separately to training our models."),
    training_limit:h("ניתן לשתף עד 200 דוגמאות. אפשר לבטל את ההסכמה ולמחוק אותן.","You can contribute up to 200 examples. Revoke consent to delete them."),
    load_required: h("יש להזין את המשקל שבוצע לפני סימון הסט. אפשר להזין 0 אם בוצע ללא משקל חיצוני.", "Enter the load used before marking the set. Enter 0 for no external load."),
    invalid_birth_date: h("יש לבחור תאריך לידה תקין שאינו בעתיד.", "Choose a valid date of birth that is not in the future."),
    recipe_grams_required: h(
      "למתכון נדרש משקל בגרמים לכל מרכיב, כולל נוזלים.",
      "Recipes require a weight in grams for each ingredient, including liquids.",
    ),
    release_pending: h(
      "האזור האישי ייפתח לאחר השלמת עדכון הכניסה והממשק.",
      "Personal tracking opens after the coordinated login and client release.",
    ),
    session_required: h(
      "יש להיכנס מחדש עם ה־PIN הקיים.",
      "Sign in again with your existing PIN.",
    ),
    session_mismatch: h(
      "החשבון התחלף. יש להיכנס מחדש.",
      "Account changed. Sign in again.",
    ),
    not_configured: h(
      "שירות ה־AI עדיין לא הוגדר או אינו זמין. אפשר להמשיך להזין ולערוך ידנית.",
      "The AI service is not configured or available. You can continue entering and editing manually.",
    ),
    rate_limited: h(
      "מכסת הספק נוצלה או נשלחו בקשות מהר מדי. אפשר להמשיך ידנית ולנסות שוב מאוחר יותר.",
      "Provider quota or rate limit reached. Continue manually and retry later.",
    ),
    analysis_busy: h(
      "הניתוח עדיין מתבצע. נסו שוב בעוד רגע.",
      "Analysis is still in progress. Try again shortly.",
    ),
    version_conflict: h(
      "הרשומה השתנתה במכשיר אחר. בחרו איזו גרסה לשמור.",
      "This record changed on another device. Choose which version to keep.",
    ),
    invalid_image: h(
      "לא ניתן לקרוא את התמונה. נסו צילום JPEG ברור יותר.",
      "Could not read this image. Try a clearer JPEG photo.",
    ),
    invalid_output: h(
      "לא התקבלה הערכה תקינה. נסו צילום ברור יותר או הזנה ידנית.",
      "The estimate was invalid. Try a clearer image or manual entry.",
    ),
    provider_failed: h(
      "ספק הנתונים אינו זמין כרגע. נסו שוב או הזינו ידנית.",
      "The data provider is unavailable. Retry or enter manually.",
    ),
    adult_profile_required: h(
      "לחישוב אוטומטי נדרשים פרטי גוף מלאים וגיל 18 ומעלה.",
      "Automatic goals require a complete adult profile (18+).",
    ),
  };
  return (
    <p
      role="alert"
      className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive"
    >
      {messages[error] ??
        h(
          "לא ניתן לשמור או לטעון כרגע. בדקו את הנתונים ואת החיבור ונסו שוב.",
          "Unable to save or load. Check the values and connection, then retry.",
        )}
    </p>
  );
}
export function AsyncButton({
  children,
  onClick,
  ...props
}: React.ComponentProps<typeof Button>) {
  return (
    <Button {...props} onClick={onClick}>
      {children}
    </Button>
  );
}
export const round = (n: number | null | undefined) =>
  n == null ? "—" : Math.round(n).toLocaleString();
