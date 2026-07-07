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
  const photoUrl = member?.avatar_photo_url;

  if (photoUrl && photoUrl !== failedUrl) {
    return (
      // eslint-disable-next-line @next/next/no-img-element -- small inline avatar, not worth next/image's layout ceremony here
      <img
        src={photoUrl}
        alt=""
        className={cn("shrink-0 rounded-full object-cover", className)}
        onError={() => setFailedUrl(photoUrl)}
      />
    );
  }
  return <span className={emojiClassName}>{member?.avatar_emoji ?? fallbackEmoji}</span>;
}
