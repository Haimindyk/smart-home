"use client";

import { useRef, useState } from "react";
import { Bot, ImagePlus, Loader2, Send, X } from "lucide-react";
import { useAppStore } from "@/lib/store/app-store";
import { useT } from "@/lib/i18n/store";
import { askAssistant } from "@/lib/assistant/client";
import { applyProposedAction } from "@/lib/assistant/apply-actions";
import type { ProposedAction } from "@/lib/assistant/types";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { toast } from "sonner";

type ChatMessage = {
  id: string;
  role: "user" | "assistant";
  text: string;
  imagePreview?: string;
  proposedActions?: (ProposedAction & { applied?: boolean })[];
};

function describeAction(action: ProposedAction): string {
  const { tasks, chores } = useAppStore.getState();
  switch (action.type) {
    case "create_task":
      return `➕ ${action.title}`;
    case "create_section":
      return `📁 ${action.name}`;
    case "toggle_task_completed":
      return `✅ ${tasks[action.taskId]?.title ?? action.taskId}`;
    case "create_chore":
      return `🔁 ${action.title}`;
    case "complete_chore":
      return `✅ ${chores[action.choreId]?.title ?? action.choreId}`;
    case "create_family_event":
      return `📅 ${action.title} (${action.eventDate}${action.endDate ? ` – ${action.endDate}` : ""})`;
    case "send_broadcast":
      return `📣 ${action.message}`;
  }
}

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve((reader.result as string).split(",")[1] ?? "");
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

export function AssistantDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const t = useT();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [pendingImage, setPendingImage] = useState<{ file: File; previewUrl: string } | null>(null);
  const [sending, setSending] = useState(false);

  async function submit() {
    const text = input.trim();
    if (!text && !pendingImage) return;

    const userMessage: ChatMessage = {
      id: crypto.randomUUID(),
      role: "user",
      text,
      imagePreview: pendingImage?.previewUrl,
    };
    setMessages((prev) => [...prev, userMessage]);
    setInput("");
    const image = pendingImage;
    setPendingImage(null);
    setSending(true);

    const imageBase64 = image ? await fileToBase64(image.file) : undefined;
    const result = await askAssistant({
      message: text || undefined,
      imageBase64,
      imageMimeType: image?.file.type,
    });
    setSending(false);

    if ("error" in result) {
      const key =
        result.error === "rate_limited"
          ? "assistantRateLimited"
          : result.error === "assistant_not_configured"
            ? "assistantNotConfigured"
            : "assistantUnavailable";
      setMessages((prev) => [...prev, { id: crypto.randomUUID(), role: "assistant", text: t(key) }]);
      return;
    }

    const assistantMessageId = crypto.randomUUID();
    setMessages((prev) => [
      ...prev,
      {
        id: assistantMessageId,
        role: "assistant",
        text: result.reply || t("assistantNoReply"),
        proposedActions: result.proposedActions,
      },
    ]);

    // The user already asked for this in chat — applying it immediately
    // (rather than making them tap a second confirm button) is what "ask the
    // assistant to add milk" actually means. Each action still runs through
    // applyProposedAction, so it gets the same attribution/offline-queue/
    // realtime behavior as a human doing it directly.
    for (let i = 0; i < result.proposedActions.length; i++) {
      try {
        await applyProposedAction(result.proposedActions[i]);
        setMessages((prev) =>
          prev.map((m) =>
            m.id === assistantMessageId
              ? { ...m, proposedActions: m.proposedActions?.map((a, idx) => (idx === i ? { ...a, applied: true } : a)) }
              : m
          )
        );
      } catch {
        toast.error(t("assistantActionFailed"));
      }
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="flex max-h-[85vh] flex-col sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Bot className="size-4" /> {t("assistantTitle")}
          </DialogTitle>
        </DialogHeader>

        <div className="flex flex-1 flex-col gap-3 overflow-y-auto py-2">
          {messages.length === 0 && (
            <p className="py-8 text-center text-sm text-muted-foreground">{t("assistantEmptyState")}</p>
          )}
          {messages.map((msg) => (
            <div key={msg.id} className={cn("flex flex-col gap-1.5", msg.role === "user" ? "items-end" : "items-start")}>
              <div
                dir="auto"
                className={cn(
                  "max-w-[85%] rounded-2xl px-3.5 py-2 text-sm",
                  msg.role === "user" ? "bg-primary text-primary-foreground" : "bg-muted"
                )}
              >
                {msg.imagePreview && (
                  // eslint-disable-next-line @next/next/no-img-element -- small inline chat preview
                  <img src={msg.imagePreview} alt="" className="mb-1.5 max-h-40 rounded-lg object-cover" />
                )}
                {msg.text}
              </div>
              {msg.proposedActions && msg.proposedActions.length > 0 && (
                <div className="flex flex-wrap gap-1.5">
                  {msg.proposedActions.map((action, i) => (
                    <span
                      key={i}
                      dir="auto"
                      className={cn(
                        "rounded-full border px-3 py-1.5 text-xs font-medium",
                        action.applied
                          ? "border-emerald-600/40 bg-emerald-600/10 text-emerald-700 dark:text-emerald-400"
                          : "border-primary/30 bg-primary/10 text-primary"
                      )}
                    >
                      {action.applied ? "✓ " : ""}
                      {describeAction(action)}
                    </span>
                  ))}
                </div>
              )}
            </div>
          ))}
          {sending && (
            <div className="flex items-center gap-2 self-start rounded-2xl bg-muted px-3.5 py-2 text-sm text-muted-foreground">
              <Loader2 className="size-3.5 animate-spin" /> {t("assistantThinking")}
            </div>
          )}
        </div>

        <div className="flex flex-col gap-2 border-t pt-3">
          {pendingImage && (
            <div className="flex items-center gap-2 rounded-lg border p-1.5">
              {/* eslint-disable-next-line @next/next/no-img-element -- small inline attach preview */}
              <img src={pendingImage.previewUrl} alt="" className="size-10 rounded-md object-cover" />
              <span className="flex-1 truncate text-xs text-muted-foreground">{pendingImage.file.name}</span>
              <Button variant="ghost" size="icon" className="size-6" onClick={() => setPendingImage(null)}>
                <X className="size-3.5" />
              </Button>
            </div>
          )}
          <div className="flex items-end gap-2">
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0];
                e.target.value = "";
                if (file) setPendingImage({ file, previewUrl: URL.createObjectURL(file) });
              }}
            />
            <Button
              type="button"
              variant="outline"
              size="icon"
              onClick={() => fileInputRef.current?.click()}
              aria-label={t("assistantAttachImage")}
              title={t("assistantAttachImage")}
            >
              <ImagePlus className="size-4" />
            </Button>
            <Textarea
              dir="auto"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  void submit();
                }
              }}
              placeholder={t("assistantPlaceholder")}
              rows={1}
              className="max-h-32 min-h-9 flex-1 resize-none"
            />
            <Button
              type="button"
              size="icon"
              onClick={() => void submit()}
              disabled={sending || (!input.trim() && !pendingImage)}
              aria-label={t("send")}
            >
              <Send className="size-4 rtl:-scale-x-100" />
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
