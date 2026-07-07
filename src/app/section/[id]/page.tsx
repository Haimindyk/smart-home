"use client";

import { useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { ArrowRight, ArrowLeft, MoreVertical, Trash2, Pencil } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useLocaleStore, useT } from "@/lib/i18n/store";
import { AppHeader } from "@/components/nav/app-header";
import { TaskList } from "@/components/tasks/task-list";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

export default function SectionPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const locale = useLocaleStore((s) => s.locale);
  const section = useAppStore((s) => s.sections[params.id]);
  const renameSection = useAppStore((s) => s.renameSection);
  const deleteSection = useAppStore((s) => s.deleteSection);
  const t = useT();
  const [renaming, setRenaming] = useState(false);
  const [name, setName] = useState(section?.name ?? "");

  const BackIcon = locale === "he" ? ArrowRight : ArrowLeft;

  if (!section) {
    return (
      <div className="flex min-h-full flex-col">
        <AppHeader />
      </div>
    );
  }

  return (
    <div className="flex min-h-full flex-1 flex-col">
      <AppHeader />
      <main className="mx-auto w-full max-w-2xl flex-1 px-4 py-6">
        <div className="mb-4 flex items-center gap-2">
          <Button variant="ghost" size="icon" onClick={() => router.push("/")}>
            <BackIcon className="size-4" />
          </Button>

          {renaming ? (
            <Input
              autoFocus
              dir="auto"
              value={name}
              onChange={(e) => setName(e.target.value)}
              onBlur={() => {
                if (name.trim()) void renameSection(section.id, name.trim(), section.emoji ?? undefined);
                setRenaming(false);
              }}
              onKeyDown={(e) => e.key === "Enter" && e.currentTarget.blur()}
              className="flex-1 text-xl font-bold"
            />
          ) : (
            <h1 className="flex-1 text-2xl font-bold" dir="auto">
              {section.emoji} {section.name}
            </h1>
          )}

          <DropdownMenu>
            <DropdownMenuTrigger render={<Button variant="ghost" size="icon" />}>
              <MoreVertical className="size-4" />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem
                onClick={() => {
                  setName(section.name);
                  setRenaming(true);
                }}
              >
                <Pencil className="size-4" /> {t("rename")}
              </DropdownMenuItem>
              <DropdownMenuItem
                variant="destructive"
                onClick={() => {
                  void deleteSection(section.id);
                  router.push("/");
                }}
              >
                <Trash2 className="size-4" /> {t("delete")}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

        {section.description && (
          <p dir="auto" className="mb-4 rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground">
            {section.description}
          </p>
        )}

        <TaskList section={section} />
      </main>
    </div>
  );
}
