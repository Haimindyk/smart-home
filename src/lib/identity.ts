"use client";

import { create } from "zustand";
import { persist } from "zustand/middleware";

/**
 * Who is "acting" on this device — purely for attribution (created_by /
 * completed_by / assignee). This is NOT an access-control layer: the app has
 * no login, anyone with the link can use it. Picking a name just makes
 * "who completed this" mean something.
 */
type IdentityState = {
  actingMemberId: string | null;
  setActingMemberId: (id: string | null) => void;
};

export const useIdentity = create<IdentityState>()(
  persist(
    (set) => ({
      actingMemberId: null,
      setActingMemberId: (id) => set({ actingMemberId: id }),
    }),
    { name: "kh-identity" }
  )
);
