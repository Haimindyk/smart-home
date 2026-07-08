"use client";

import { useState } from "react";
import { Megaphone } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { toast } from "sonner";

/**
 * Client-side attribution only, not access control (this app has no auth —
 * see src/lib/identity.ts). Hiding the button for everyone but Haim just
 * keeps the UI uncluttered; it doesn't stop anyone from sending one.
 */
export const BROADCAST_SENDER_EMAIL = "haim_indyk@icloud.com";

export function BroadcastMessageDialog({
  open,
  onOpenChange,
  actorId,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  actorId: string | null;
}) {
  const sendBroadcastMessage = useAppStore((s) => s.sendBroadcastMessage);
  const t = useT();
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);

  async function submit() {
    if (!message.trim()) return;
    setSending(true);
    await sendBroadcastMessage(message.trim(), actorId);
    setSending(false);
    setMessage("");
    onOpenChange(false);
    toast(t("messageSent"));
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Megaphone className="size-4" /> {t("sendMessage")}
          </DialogTitle>
        </DialogHeader>
        <Textarea
          dir="auto"
          autoFocus
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          placeholder={t("sendMessagePlaceholder")}
          rows={4}
        />
        <DialogFooter>
          <Button onClick={() => void submit()} disabled={!message.trim() || sending}>
            {t("send")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
