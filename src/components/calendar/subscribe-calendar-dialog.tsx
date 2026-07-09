"use client";

import { useState } from "react";
import { CalendarPlus, Check, Copy } from "lucide-react";
import { useT } from "@/lib/i18n/store";
import { calendarFeedUrl, calendarWebcalUrl } from "@/lib/calendar/feed-url";
import { Button, buttonVariants } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { toast } from "sonner";

/** Explains what to actually do with the calendar subscription link — a
 * bare "copy link" button (the original implementation) left people with a
 * URL on their clipboard and no idea what came next. */
export function SubscribeCalendarDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const t = useT();
  const [copied, setCopied] = useState(false);

  async function copyLink() {
    await navigator.clipboard.writeText(calendarFeedUrl());
    setCopied(true);
    toast.success(t("calendarLinkCopied"));
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <CalendarPlus className="size-4" /> {t("subscribeCalendar")}
          </DialogTitle>
        </DialogHeader>

        <div className="flex min-w-0 flex-col gap-4 text-sm">
          <div className="flex flex-col gap-1.5">
            {/* webcal:// (rather than https://) is what makes iOS/macOS
                Calendar and many Android calendar apps recognize this as a
                subscription and open their own add-calendar screen directly. */}
            <a href={calendarWebcalUrl()} className={cn(buttonVariants({ variant: "default" }), "w-full gap-2")}>
              <CalendarPlus className="size-4" />
              {t("openInCalendarApp")}
            </a>
            <p className="text-xs text-muted-foreground">{t("openInCalendarAppHint")}</p>
          </div>

          <div className="flex min-w-0 items-center gap-2 rounded-lg border p-2">
            <code dir="ltr" className="min-w-0 flex-1 truncate text-xs text-muted-foreground">
              {calendarFeedUrl()}
            </code>
            <Button variant="outline" size="icon-sm" onClick={() => void copyLink()} aria-label={t("copyCalendarLink")}>
              {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
            </Button>
          </div>

          <div className="flex flex-col gap-2 rounded-lg bg-muted/40 p-3">
            <div>
              <p className="font-medium">{t("calendarInstructionsGoogleTitle")}</p>
              <p dir="auto" className="text-muted-foreground">
                {t("calendarInstructionsGoogleBody")}
              </p>
            </div>
            <div>
              <p className="font-medium">{t("calendarInstructionsAppleTitle")}</p>
              <p dir="auto" className="text-muted-foreground">
                {t("calendarInstructionsAppleBody")}
              </p>
            </div>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
