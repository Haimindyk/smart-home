"use client";

import { useEffect, useState } from "react";

/** A reactive "current time" so due/overdue checks don't call `Date.now()`
 * directly during render (impure — React Compiler flags it). Refreshes on
 * an interval so a chore due at 14:00 still flips to overdue without a
 * page reload. */
export function useNow(intervalMs = 30_000) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);
  return now;
}
