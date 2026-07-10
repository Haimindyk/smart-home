"use client";

import { create } from "zustand";

/** Shared so a personal note card (rendered on the dashboard, a sibling of
 * AppHeader) can open the same assistant chat dialog AppHeader's button
 * opens — letting a private check-in from Mika be answered in the actual
 * conversation instead of being a dead-end notification. */
export const useAssistantOpen = create<{ open: boolean; setOpen: (open: boolean) => void }>((set) => ({
  open: false,
  setOpen: (open) => set({ open }),
}));
