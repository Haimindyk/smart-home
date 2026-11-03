"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useHealthText } from "@/lib/health/i18n";
import { useLocaleStore } from "@/lib/i18n/store";

const DAY_MS = 86_400_000;
const dateAtNoon = (value:string) => new Date(`${value}T12:00:00Z`);

export function WeekPicker({date,today,onChange}:{date:string;today:string;onChange:(date:string)=>void}) {
  const h=useHealthText();
  const locale=useLocaleStore(s=>s.locale);
  const rail=useRef<HTMLDivElement>(null);
  const scrollFrame=useRef<number | null>(null);
  const [view,setView]=useState({selected:date,visible:date});
  const visibleDate=view.selected===date?view.visible:date;
  const days=useMemo(()=>{
    const selected=dateAtNoon(date).getTime();
    const language=locale==="he"?"he-IL":"en-US";
    const weekday=new Intl.DateTimeFormat(language,{weekday:"narrow",timeZone:"UTC"});
    const fullDate=new Intl.DateTimeFormat(language,{dateStyle:"full",timeZone:"UTC"});
    return Array.from({length:181},(_,index)=>{
      const value=new Date(selected+(index-90)*DAY_MS);
      return {date:value.toISOString().slice(0,10),day:value.getUTCDate(),label:weekday.format(value),fullLabel:fullDate.format(value)};
    });
  },[date,locale]);

  useEffect(()=>{
    const container=rail.current;
    const selected=container?.querySelector<HTMLElement>("[aria-pressed='true']");
    if(!container||!selected)return;
    const containerRect=container.getBoundingClientRect();
    const selectedRect=selected.getBoundingClientRect();
    container.scrollBy({left:selectedRect.left+selectedRect.width/2-containerRect.left-containerRect.width/2,behavior:"instant"});
  },[date,locale]);

  useEffect(()=>()=>{
    if(scrollFrame.current!==null)cancelAnimationFrame(scrollFrame.current);
  },[]);

  function updateVisibleDate() {
    if(scrollFrame.current!==null)return;
    scrollFrame.current=requestAnimationFrame(()=>{
      scrollFrame.current=null;
      const container=rail.current;
      if(!container)return;
      const rect=container.getBoundingClientRect();
      const center=rect.left+rect.width/2;
      let nearest:string | undefined;
      let distance=Infinity;
      for(const day of container.querySelectorAll<HTMLButtonElement>("button[data-date]")) {
        const dayRect=day.getBoundingClientRect();
        const delta=Math.abs(dayRect.left+dayRect.width/2-center);
        if(delta<distance){distance=delta;nearest=day.dataset.date;}
      }
      if(nearest){
        const visible=nearest;
        setView(previous=>previous.selected===date&&previous.visible===visible?previous:{selected:date,visible});
      }
    });
  }

  const month=new Intl.DateTimeFormat(locale==="he"?"he-IL":"en-US",{month:"long",year:"numeric",timeZone:"UTC"}).format(dateAtNoon(visibleDate));
  return <section className="health-week-picker mb-6" aria-label={h("בחירת תאריך", "Date navigation")}>
    <div className="date-wheel-heading"><span aria-live="polite" aria-atomic="true">{month}</span>{date!==today&&<button className="week-today" onClick={()=>onChange(today)}>{h("חזרה להיום","Back to today")}</button>}</div>
    <div ref={rail} onScroll={updateVisibleDate} className="health-date-wheel" role="group" aria-label={h("גלילת תאריכים","Scroll through dates")}>
      {days.map(d=><button type="button" key={d.date} data-date={d.date} onClick={()=>onChange(d.date)} aria-label={d.fullLabel} aria-pressed={date===d.date} className={date===d.date?"selected":""}><span>{d.label}</span><strong>{d.day}</strong><i/></button>)}
    </div>
  </section>;
}
