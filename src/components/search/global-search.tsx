"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Fuse from "fuse.js";
import { useAppStore } from "@/lib/store/app-store";
import { useSearchOpen } from "@/lib/search-ui-state";
import { useT } from "@/lib/i18n/store";
import {
  Command,
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";

type SearchItem = {
  id: string;
  kind: "section" | "task" | "chore";
  title: string;
  subtitle?: string;
  sectionId: string;
  tags?: string[];
};

export function GlobalSearch() {
  const open = useSearchOpen((s) => s.open);
  const setOpen = useSearchOpen((s) => s.setOpen);
  const sections = useAppStore((s) => s.sections);
  const tasks = useAppStore((s) => s.tasks);
  const chores = useAppStore((s) => s.chores);
  const members = useAppStore((s) => s.members);
  const router = useRouter();
  const t = useT();

  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "k" && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        setOpen(!useSearchOpen.getState().open);
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [setOpen]);

  const items = useMemo<SearchItem[]>(() => {
    const sectionItems = Object.values(sections)
      .filter((s) => !s.deleted_at)
      .map((s) => ({ id: s.id, kind: "section" as const, title: s.name, sectionId: s.id }));

    const taskItems = Object.values(tasks)
      .filter((tsk) => !tsk.deleted_at)
      .map((tsk) => ({
        id: tsk.id,
        kind: "task" as const,
        title: tsk.title,
        subtitle: [
          tsk.notes ?? "",
          tsk.assignee_member_id ? members[tsk.assignee_member_id]?.display_name : "",
        ]
          .filter(Boolean)
          .join(" · "),
        sectionId: tsk.section_id,
        tags: tsk.tags,
      }));

    const choreItems = Object.values(chores)
      .filter((c) => !c.deleted_at)
      .map((c) => ({ id: c.id, kind: "chore" as const, title: c.title, sectionId: c.section_id }));

    return [...sectionItems, ...taskItems, ...choreItems];
  }, [sections, tasks, chores, members]);

  const fuse = useMemo(
    () => new Fuse(items, { keys: ["title", "subtitle", "tags"], threshold: 0.35 }),
    [items]
  );

  const [query, setQuery] = useState("");
  const results = query ? fuse.search(query).map((r) => r.item).slice(0, 20) : items.slice(0, 20);

  function go(item: SearchItem) {
    setOpen(false);
    setQuery("");
    if (item.kind === "chore") router.push("/chores");
    else router.push(`/section/${item.sectionId}`);
  }

  return (
    <CommandDialog open={open} onOpenChange={setOpen} title={t("search")} description={t("searchPlaceholder")}>
      <Command shouldFilter={false}>
        <CommandInput placeholder={t("searchPlaceholder")} value={query} onValueChange={setQuery} />
        <CommandList>
          <CommandEmpty>{t("emptySearch")}</CommandEmpty>
          <CommandGroup>
            {results.map((item) => (
              <CommandItem key={`${item.kind}-${item.id}`} value={`${item.kind}-${item.id}`} onSelect={() => go(item)}>
                <span className="me-2 text-xs text-muted-foreground">
                  {item.kind === "section" ? "📁" : item.kind === "chore" ? "🏠" : "✓"}
                </span>
                <span dir="auto">{item.title}</span>
                {item.subtitle && <span className="ms-auto truncate text-xs text-muted-foreground">{item.subtitle}</span>}
              </CommandItem>
            ))}
          </CommandGroup>
        </CommandList>
      </Command>
    </CommandDialog>
  );
}
