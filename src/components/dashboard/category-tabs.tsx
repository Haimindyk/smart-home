"use client";

import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";
import type { Section } from "@/types/domain";

export function CategoryTabs({ sections }: { sections: Section[] }) {
  const [activeId, setActiveId] = useState<string | null>(sections[0]?.id ?? null);
  const observerRef = useRef<IntersectionObserver | null>(null);
  const tabRefs = useRef<Record<string, HTMLButtonElement | null>>({});

  // Keep the highlighted tab scrolled into view within its own horizontal
  // strip — otherwise scrolling the page moves the highlight off-screen to
  // the side with nothing on screen to show which tab is active. `inline`
  // handles the strip's own scroll; `block: "nearest"` keeps this from also
  // scrolling the page vertically.
  useEffect(() => {
    if (!activeId) return;
    tabRefs.current[activeId]?.scrollIntoView({ behavior: "smooth", inline: "center", block: "nearest" });
  }, [activeId]);

  useEffect(() => {
    const elements = sections
      .map((s) => document.getElementById(`section-${s.id}`))
      .filter((el): el is HTMLElement => !!el);
    if (elements.length === 0) return;

    observerRef.current?.disconnect();
    const visible = new Map<string, number>();
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          visible.set(entry.target.id, entry.intersectionRatio);
        }
        let bestId: string | null = null;
        let bestRatio = 0;
        for (const [id, ratio] of visible) {
          if (ratio > bestRatio) {
            bestRatio = ratio;
            bestId = id;
          }
        }
        if (bestId) setActiveId(bestId.replace("section-", ""));
      },
      { rootMargin: "-120px 0px -60% 0px", threshold: [0, 0.25, 0.5, 0.75, 1] }
    );
    elements.forEach((el) => observer.observe(el));
    observerRef.current = observer;
    return () => observer.disconnect();
  }, [sections]);

  function jumpTo(id: string) {
    setActiveId(id);
    document.getElementById(`section-${id}`)?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  if (sections.length === 0) return null;

  return (
    <div className="sticky top-[68px] z-30 -mx-4 mb-4 px-4">
      <div className="glass surface-shadow w-full overflow-x-auto rounded-full px-2 py-2 ring-1 ring-border/40">
        <div className="flex w-max gap-1.5">
          {sections.map((section) => (
            <button
              key={section.id}
              ref={(el) => {
                tabRefs.current[section.id] = el;
              }}
              onClick={() => jumpTo(section.id)}
              className={cn(
                "flex shrink-0 items-center gap-1.5 rounded-full px-3.5 py-1.5 text-sm font-semibold transition-[background-color,color,transform] duration-150 ease-(--ease-premium)",
                activeId === section.id
                  ? "scale-105 bg-primary text-primary-foreground shadow-[0_4px_14px_-2px_oklch(0.64_0.15_45/0.5)]"
                  : "text-muted-foreground hover:bg-accent hover:text-foreground"
              )}
            >
              <span>{section.emoji}</span>
              <span dir="auto">{section.name}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
