"use client";
import Image from "next/image";
import { Utensils } from "lucide-react";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { useHealthStore } from "@/lib/health/store";
import { useHealthText } from "@/lib/health/i18n";

export function MealImage({ path, thumbnail = false, preview = false, onOpen, displayOnly=false, alt }: {
  path: string; thumbnail?: boolean; preview?: boolean; onOpen?: () => void; displayOnly?:boolean; alt?:string;
}) {
  const h = useHealthText(), owner = useHealthStore((s) => s.owner);
  const [resolved, setResolved] = useState<{ path: string; owner: string; url: string } | null>(null);
  useEffect(() => {
    let cancelled = false;
    if (owner && path.startsWith(owner + "/")) void createClient().storage.from("health-images").createSignedUrl(path, 300).then(({ data }) => {
      if (!cancelled && data?.signedUrl) setResolved({ path, owner, url: data.signedUrl });
    }).catch(() => { /* Photo failure must not block editing the meal. */ });
    return () => { cancelled = true; };
  }, [path, owner]);
  const url = resolved?.path === path && resolved.owner === owner ? resolved.url : "";
  const content = url && (thumbnail || preview)
    ? <Image unoptimized width={preview ? 640 : 64} height={preview ? 360 : 64} src={url} alt={alt??h("תמונת הארוחה", "Meal photo")} className={preview ? "health-meal-preview" : "health-meal-thumb"} />
    : thumbnail ? <span className="health-meal-thumb health-meal-placeholder" aria-hidden="true"><Utensils size={23} /></span> : h("הצגת תמונת הארוחה", "View meal photo");
  if(displayOnly)return content;
  if (onOpen) return <button type="button" className="shrink-0" onClick={onOpen} aria-label={h("פתיחת הארוחה ותיקון הזיהוי", "Open meal and correct recognition")}>{content}</button>;
  return url ? <a href={url} target="_blank" rel="noreferrer" aria-label={h("פתיחת התמונה", "View photo")}>{content}</a> : null;
}
