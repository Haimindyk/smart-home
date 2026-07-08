"use client";

import { useState } from "react";
import { cn } from "@/lib/utils";

type AvatarLike = { avatar_photo_url?: string | null; avatar_emoji?: string | null } | undefined;

/**
 * Renders a member's avatar: their uploaded photo if they have one,
 * otherwise their emoji. Used everywhere an avatar shows up (header,
 * assignee badges, history, push notification icons) so photo vs. emoji
 * only needs deciding in one place. Falls back to the emoji if the photo
 * URL fails to load (deleted storage object, transient network issue).
 */
export function MemberAvatar({
  member,
  className,
  emojiClassName,
  fallbackEmoji = "🙂",
}: {
  member: AvatarLike;
  className?: string;
  emojiClassName?: string;
  /** Shown when there's no member at all (e.g. a history entry with no actor) — vs. a real member who just has no emoji set. */
  fallbackEmoji?: string;
}) {
  const [failedUrl, setFailedUrl] = useState<string | null>(null);
  const [loadedUrl, setLoadedUrl] = useState<string | null>(null);
  const photoUrl = member?.avatar_photo_url;
  const emoji = <span className={emojiClassName}>{member?.avatar_emoji ?? fallbackEmoji}</span>;

  if (!photoUrl || photoUrl === failedUrl) return emoji;

  return (
    <span
      className={cn(
        "relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full",
        className
      )}
    >
      {/* Shown until the photo has fully decoded — without this, a slow
          connection painted whatever partial/garbled pixel data it had
          received so far instead of just waiting for a clean image. */}
      {photoUrl !== loadedUrl && emoji}
      {/* eslint-disable-next-line @next/next/no-img-element -- small inline avatar, not worth next/image's layout ceremony here */}
      <img
        src={photoUrl}
        alt=""
        className={cn("absolute inset-0 size-full object-cover", photoUrl === loadedUrl ? "opacity-100" : "opacity-0")}
        onLoad={() => setLoadedUrl(photoUrl)}
        onError={() => setFailedUrl(photoUrl)}
      />
    </span>
  );
}
