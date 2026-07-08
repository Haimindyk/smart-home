"use client";

import { useEffect, useState } from "react";
import { FileText, Music, Video, File as FileIcon, X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useAppStore } from "@/lib/store/app-store";
import type { Attachment } from "@/types/domain";

const KIND_ICON: Record<string, typeof FileIcon> = {
  pdf: FileText,
  audio: Music,
  video: Video,
  file: FileIcon,
};

/** Attachments live in a private storage bucket, so viewing one needs a
 * freshly signed URL rather than a stable public link. */
export function AttachmentRow({ attachment }: { attachment: Attachment }) {
  const deleteAttachment = useAppStore((s) => s.deleteAttachment);
  const [url, setUrl] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const supabase = createClient();
    supabase.storage
      .from("attachments")
      .createSignedUrl(attachment.storage_path, 3600)
      .then(({ data }) => {
        if (!cancelled && data) setUrl(data.signedUrl);
      });
    return () => {
      cancelled = true;
    };
  }, [attachment.storage_path]);

  const Icon = KIND_ICON[attachment.kind] ?? FileIcon;

  return (
    <div className="group relative flex w-16 shrink-0 flex-col items-center gap-1">
      <a
        href={url ?? undefined}
        target="_blank"
        rel="noreferrer"
        className="flex size-16 items-center justify-center overflow-hidden rounded-xl border bg-muted/50"
      >
        {attachment.kind === "image" && url ? (
          // eslint-disable-next-line @next/next/no-img-element -- small inline thumbnail behind a signed URL, not worth next/image here
          <img src={url} alt="" className="size-full object-cover" />
        ) : (
          <Icon className="size-6 text-muted-foreground" />
        )}
      </a>
      <button
        type="button"
        onClick={() => void deleteAttachment(attachment.id)}
        className="absolute -end-1 -top-1 flex size-5 items-center justify-center rounded-full bg-destructive text-destructive-foreground opacity-0 transition-opacity group-hover:opacity-100"
        aria-label="Delete"
      >
        <X className="size-3" />
      </button>
      <span className="max-w-16 truncate text-[10px] text-muted-foreground" dir="auto">
        {attachment.file_name}
      </span>
    </div>
  );
}
