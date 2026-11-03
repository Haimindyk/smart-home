"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { useHealthStore } from "@/lib/health/store";
import { Delete, House } from "lucide-react";
import { useIdentity } from "@/lib/identity";
import { useT } from "@/lib/i18n/store";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";

const PIN_LENGTH = 4;
const KEYS = [
  "1",
  "2",
  "3",
  "4",
  "5",
  "6",
  "7",
  "8",
  "9",
  "",
  "0",
  "back",
] as const;

export function IdentityGate({ children }: { children: React.ReactNode }) {
  const actingMemberId = useIdentity((s) => s.actingMemberId);
  const setActingMemberId = useIdentity((s) => s.setActingMemberId);

  const t = useT();
  const [pin, setPin] = useState("");
  const [shake, setShake] = useState(false);
  const [busy, setBusy] = useState(false);
  const [verified, setVerified] = useState(false);
  const [checking, setChecking] = useState(true);
  const [loginError, setLoginError] = useState("");

  useEffect(() => {
    let cancelled = false;
    const client = createClient();
    const check = async () => {
      if (!navigator.onLine) {
        const {
          data: { session },
        } = await client.auth.getSession();
        const cached = JSON.parse(
          localStorage.getItem("kh-auth-owner") ?? "null",
        );
        if (!cancelled) {
          setVerified(
            Boolean(
              session &&
                session.expires_at &&
                session.expires_at * 1000 > Date.now() &&
                cached?.userId === session.user.id &&
                cached?.memberId === actingMemberId,
            ),
          );
          setChecking(false);
        }
        return;
      }
      const {
        data: { user },
      } = await client.auth.getUser();
      const { data: member } = user
        ? await client
            .from("members")
            .select("id")
            .eq("user_id", user.id)
            .maybeSingle()
        : { data: null };
      if (cancelled) return;
      if (member && (!actingMemberId || actingMemberId === member.id)) {
        localStorage.setItem(
          "kh-auth-owner",
          JSON.stringify({ memberId: member.id, userId: user!.id }),
        );
        setActingMemberId(member.id);
        setVerified(true);
      } else {
        setVerified(false);
        if (actingMemberId) setActingMemberId(null);
      }
      setChecking(false);
    };
    void check();
    const {
      data: { subscription },
    } = client.auth.onAuthStateChange((event) => {
      if (event === "SIGNED_OUT") {
        setVerified(false);
        localStorage.removeItem("kh-auth-owner");
        setActingMemberId(null);
        void useHealthStore.getState().reset();
      }
    });
    return () => {
      cancelled = true;
      subscription.unsubscribe();
    };
  }, [actingMemberId, setActingMemberId]);

  useEffect(() => {
    // Switching a shared-device identity must never leave private rows behind.
    return useIdentity.subscribe((next, prev) => {
      if (next.actingMemberId !== prev.actingMemberId && prev.actingMemberId) {
        void useHealthStore.getState().reset();
      }
    });
  }, []);

  async function press(key: string) {
    if (busy) return;
    if (key === "back") {
      setPin((p) => p.slice(0, -1));
      return;
    }
    if (!key || pin.length >= PIN_LENGTH) return;

    const next = pin + key;
    setPin(next);
    if (next.length < PIN_LENGTH) return;

    setBusy(true);
    setLoginError("");
    try {
      const client = createClient();
      const { data, error } = await client.functions.invoke("pin-login", {
        body: { pin: next },
      });
      if (error || data?.error || !data?.access_token || !data?.refresh_token)
        throw new Error(data?.error ?? "connection_failed");
      const { error: sessionError } = await client.auth.setSession({
        access_token: data.access_token,
        refresh_token: data.refresh_token,
      });
      if (sessionError) throw sessionError;
      const {
        data: { session },
      } = await client.auth.getSession();
      localStorage.setItem(
        "kh-auth-owner",
        JSON.stringify({ memberId: data.memberId, userId: session?.user.id }),
      );
      setActingMemberId(data.memberId);
      setVerified(true);
      setPin("");
    } catch (e) {
      setShake(true);
      setPin("");
      setLoginError(
        e instanceof Error && e.message === "invalid_pin"
          ? t("wrongPin")
          : "לא ניתן להתחבר כרגע / Unable to sign in. Try again shortly.",
      );
      setTimeout(() => setShake(false), 500);
    } finally {
      setBusy(false);
    }
  }

  if (verified && actingMemberId) return <>{children}</>;
  if (checking)
    return (
      <div
        className="flex min-h-screen items-center justify-center"
        role="status"
      >
        …
      </div>
    );

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center overflow-hidden bg-background p-6">
      <div className="pointer-events-none absolute -top-24 start-1/2 size-96 -translate-x-1/2 rounded-full bg-amber-400/10 blur-3xl" />
      <Card className="glass surface-shadow relative w-full max-w-xs gap-5 rounded-3xl p-7 text-center ring-1 ring-border/40">
        <div>
          <div className="mx-auto mb-5 flex size-16 items-center justify-center rounded-[22px] bg-amber-100 text-amber-700"><House size={30}/></div>
          <h1 className="text-2xl font-bold tracking-tight">
            {t("whoAreYou")}
          </h1>
          <p className="mt-1.5 text-sm text-muted-foreground">
            {t("enterYourCode")}
          </p>
        </div>

        <div
          className={cn("flex justify-center gap-3", shake && "animate-shake")}
          role="status"
          aria-live="polite"
        >
          {Array.from({ length: PIN_LENGTH }).map((_, i) => (
            <span
              key={i}
              className={cn(
                "size-3.5 rounded-full border-2 border-primary/40 transition-all",
                i < pin.length && "scale-110 border-primary bg-primary",
              )}
            />
          ))}
          <span className="sr-only">{shake ? t("wrongPin") : ""}</span>
        </div>

        {loginError && (
          <p role="alert" className="text-sm text-destructive">
            {loginError}
          </p>
        )}
        <div className="grid grid-cols-3 gap-2">
          {KEYS.map((key, i) =>
            key === "" ? (
              <span key={i} />
            ) : (
              <button
                key={i}
                type="button"
                onClick={() => press(key)}
                disabled={busy}
                aria-label={key === "back" ? t("delete") : key}
                className="flex h-12 items-center justify-center rounded-2xl border border-border/60 bg-muted/60 text-lg font-medium transition-[background-color,transform] duration-150 ease-(--ease-premium) hover:bg-accent active:scale-90"
              >
                {key === "back" ? <Delete className="size-5" /> : key}
              </button>
            ),
          )}
        </div>
      </Card>
    </div>
  );
}
