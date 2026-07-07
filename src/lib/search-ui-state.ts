"use client";

import { create } from "zustand";

export const useSearchOpen = create<{ open: boolean; setOpen: (open: boolean) => void }>((set) => ({
  open: false,
  setOpen: (open) => set({ open }),
}));
